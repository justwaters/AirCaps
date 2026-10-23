import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let capsLock = CapsLockController()
    let settings = SettingsStore()
    let permissions = PermissionsGate()
    let updateChecker = UpdateChecker()
    private(set) lazy var noiseMode = NoiseModeController(
        capsLock: capsLock,
        offMode: { [weak self] in self?.settings.offMode.asNoiseMode ?? .adaptive },
        backend: { [weak self] in (self?.settings.backendChoice ?? .hal).backend }
    )
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        // Permissions can change after launch in either direction (granted mid-
        // session, or revoked externally via System Settings while running) —
        // react to both. If Input Monitoring gets revoked while the hidutil
        // remap is still active, stop() reverts it immediately rather than
        // leaving Caps Lock dead with nothing listening to reactivate it.
        // Both start()/stop() are idempotent, safe to call redundantly.
        settings.$backendChoice
            .sink { [weak self] choice in
                self?.permissions.accessibilityRequired = choice.backend.requiresAccessibility
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            permissions.$accessibility, permissions.$inputMonitoring, permissions.$accessibilityRequired
        )
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                if self.permissions.allGranted {
                    self.capsLock.start()
                } else {
                    self.capsLock.stop()
                }
            }
            .store(in: &cancellables)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        permissions.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reverts the hidutil remap so Caps Lock resumes normal OS behavior —
        // without this, a quit-without-reboot would leave Caps Lock dead system-wide.
        capsLock.stop()
    }
}

struct MenuBarIcon: View {
    @ObservedObject var noiseMode: NoiseModeController

    var body: some View {
        switch noiseMode.status {
        case .idle(.some(let mode)):
            modeImage(mode)
        case .idle(nil):
            Image(systemName: "airpodspro")
        case .disconnected:
            Image(systemName: "hand.tap")
        case .transitioning(_, let to):
            // Show the target mode while switching rather than a spinner glyph.
            modeImage(to)
        }
    }

    /// The bundled vector icon for a mode (template, so it follows the menu
    /// bar's light/dark appearance); SF Symbol fallback when run unbundled.
    @ViewBuilder
    private func modeImage(_ mode: NoiseMode) -> some View {
        if let image = Self.icon(for: mode) {
            Image(nsImage: image)
        } else {
            Image(systemName: mode.isLEDOn ? "ear.fill" : "waveform")
        }
    }

    private static let iconHeight: CGFloat = 17
    private static var cache: [NoiseMode: NSImage] = [:]

    private static func icon(for mode: NoiseMode) -> NSImage? {
        if let cached = cache[mode] { return cached }
        guard let url = Bundle.main.url(forResource: "MenuIcon-\(mode.rawValue)", withExtension: "pdf"),
              let image = NSImage(contentsOf: url), image.size.height > 0
        else { return nil }
        image.size = NSSize(width: image.size.width * iconHeight / image.size.height, height: iconHeight)
        image.isTemplate = true
        cache[mode] = image
        return image
    }
}

@main
struct AirCapsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                noiseMode: appDelegate.noiseMode,
                settings: appDelegate.settings,
                permissions: appDelegate.permissions,
                updateChecker: appDelegate.updateChecker
            )
        } label: {
            MenuBarIcon(noiseMode: appDelegate.noiseMode)
        }

        Settings {
            SettingsView(settings: appDelegate.settings, permissions: appDelegate.permissions)
        }
    }
}
