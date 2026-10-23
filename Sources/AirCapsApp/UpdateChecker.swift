import AppKit
import Foundation

private enum UpdateCheckResult {
    case upToDate
    case updateAvailable(version: String, releaseURL: URL, dmgURL: URL?)
}

private enum UpdateCheckError: Error, LocalizedError {
    case network(Error)
    case badResponse
    case malformedRelease
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let error): return error.localizedDescription
        case .badResponse: return "GitHub returned an unexpected response."
        case .malformedRelease: return "Couldn't read the latest release's version or URL."
        case .installFailed(let reason): return reason
        }
    }
}

/// On-demand (no background polling) check against the GitHub Releases API
/// for a newer tagged version than the running app. Reports the result via
/// an NSAlert rather than in-menu state, since this is a one-shot user action.
/// When the release has an `AirCaps.dmg`, the alert offers to install it: the
/// DMG is downloaded and checked, then a small detached script swaps the app
/// bundle once this process has quit and relaunches it.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false

    private let repo = "justwaters/AirCaps"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let result = try await fetchLatestRelease()
                presentResult(result)
            } catch {
                presentError(error)
            }
        }
    }

    private func fetchLatestRelease() async throws -> UpdateCheckResult {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateCheckError.badResponse
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String,
            let htmlURLString = json["html_url"] as? String,
            let htmlURL = URL(string: htmlURLString)
        else {
            throw UpdateCheckError.malformedRelease
        }

        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        if Self.isVersion(latestVersion, newerThan: currentVersion) {
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgURL = assets
                .first { ($0["name"] as? String) == "AirCaps.dmg" }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap { URL(string: $0) }
            return .updateAvailable(version: latestVersion, releaseURL: htmlURL, dmgURL: dmgURL)
        } else {
            return .upToDate
        }
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lhsParts.count, rhsParts.count) {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private func presentResult(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "AirCaps \(currentVersion) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .updateAvailable(let version, let releaseURL, let dmgURL):
            alert.messageText = "Update Available"
            var info = "AirCaps \(version) is available (you have \(currentVersion))."
            if dmgURL != nil {
                info += "\n\nAirCaps is ad-hoc signed, so macOS may ask you to grant Input Monitoring again after updating."
                alert.addButton(withTitle: "Install Update")
            }
            alert.informativeText = info
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            let install = dmgURL != nil && response == .alertFirstButtonReturn
            let view = response == (dmgURL != nil ? .alertSecondButtonReturn : .alertFirstButtonReturn)
            if install, let dmgURL {
                startInstall(version: version, dmgURL: dmgURL)
            } else if view {
                NSWorkspace.shared.open(releaseURL)
            }
        }
    }

    // MARK: - Install

    private func startInstall(version: String, dmgURL: URL) {
        isInstalling = true
        Task {
            do {
                try await installUpdate(version: version, dmgURL: dmgURL)
            } catch {
                isInstalling = false
                presentError(error)
            }
        }
    }

    private func installUpdate(version: String, dmgURL: URL) async throws {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else {
            throw UpdateCheckError.installFailed("AirCaps isn't running from an app bundle, so it can't update itself.")
        }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateCheckError.installFailed("AirCaps can't write to \(parent.path). Download the update from the release page instead.")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCapsUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await URLSession.shared.download(from: dmgURL)
        } catch {
            throw UpdateCheckError.network(error)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateCheckError.badResponse }
        let dmg = work.appendingPathComponent("AirCaps.dmg")
        try FileManager.default.moveItem(at: downloaded, to: dmg)

        let pid = ProcessInfo.processInfo.processIdentifier
        let ownID = Bundle.main.bundleIdentifier ?? ""
        let staged = try await Task.detached {
            try Self.stageApp(from: dmg, in: work, expectedID: ownID, expectedVersion: version)
        }.value
        try Self.launchReplacer(pid: pid, target: target, staged: staged, work: work)
        NSApp.terminate(nil)
    }

    /// Mounts the DMG, copies the app out, and checks it is AirCaps at the
    /// expected version before anything touches the installed copy.
    nonisolated private static func stageApp(
        from dmg: URL, in work: URL, expectedID: String, expectedVersion: String
    ) throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path]) }

        let staged = work.appendingPathComponent("AirCaps.app")
        try run("/usr/bin/ditto", [mount.appendingPathComponent("AirCaps.app").path, staged.path])

        let plist = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == expectedID,
              plist?["CFBundleShortVersionString"] as? String == expectedVersion
        else {
            throw UpdateCheckError.installFailed("The downloaded app didn't match AirCaps \(expectedVersion); the update was not installed.")
        }
        return staged
    }

    /// Starts a detached shell script that waits for this process to exit,
    /// swaps the bundle (restoring the old one if the copy fails), clears the
    /// quarantine flag and relaunches.
    nonisolated private static func launchReplacer(pid: Int32, target: URL, staged: URL, work: URL) throws {
        let script = work.appendingPathComponent("replace.sh")
        let body = """
        #!/bin/sh
        pid="$1"; target="$2"; staged="$3"; work="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        backup="$work/old.app"
        mv "$target" "$backup" || { open "$target"; exit 1; }
        if ditto "$staged" "$target"; then
          xattr -dr com.apple.quarantine "$target" 2>/dev/null
        else
          rm -rf "$target"; mv "$backup" "$target"
        fi
        open "$target"
        rm -rf "$work"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), target.path, staged.path, work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateCheckError.installFailed("\((path as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
