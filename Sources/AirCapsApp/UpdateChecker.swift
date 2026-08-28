import AppKit
import Foundation

private enum UpdateCheckResult {
    case upToDate
    case updateAvailable(version: String, url: URL)
}

private enum UpdateCheckError: Error, LocalizedError {
    case network(Error)
    case badResponse
    case malformedRelease

    var errorDescription: String? {
        switch self {
        case .network(let error): return error.localizedDescription
        case .badResponse: return "GitHub returned an unexpected response."
        case .malformedRelease: return "Couldn't read the latest release's version or URL."
        }
    }
}

/// On-demand (no background polling) check against the GitHub Releases API
/// for a newer tagged version than the running app. Reports the result via
/// an NSAlert rather than in-menu state, since this is a one-shot user action.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var isChecking = false

    private let repo = "justwaters/AirCaps"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() {
        guard !isChecking else { return }
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
            return .updateAvailable(version: latestVersion, url: htmlURL)
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
        case .updateAvailable(let version, let url):
            alert.messageText = "Update Available"
            alert.informativeText = "AirCaps \(version) is available (you have \(currentVersion))."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
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
