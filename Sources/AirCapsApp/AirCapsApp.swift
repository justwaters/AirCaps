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
        Image(systemName: iconName)
    }

    private var iconName: String {
        switch noiseMode.status {
        case .idle(.some(let mode)): return mode.isLEDOn ? "ear.fill" : "waveform"
        case .idle(nil): return "airpodspro"
        case .transitioning: return "arrow.triangle.2.circlepath"
        }
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
