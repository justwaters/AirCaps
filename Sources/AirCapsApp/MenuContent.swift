import AirPodsCore
import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var noiseMode: NoiseModeController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionsGate
    @ObservedObject var updateChecker: UpdateChecker

    @State private var audioOutputName = "—"
    @State private var audioError: String?

    var body: some View {
        Group {
            if !permissions.allGranted {
                permissionsWarning
                Divider()
            }

            statusText

            if let error = noiseMode.lastError {
                Text("Noise mode error: \(error)")
                    .foregroundColor(.red)
            }

            Divider()

            Menu("Set Noise Mode") {
                ForEach(NoiseMode.allCases, id: \.self) { mode in
                    Button(mode.displayName) { noiseMode.requestMode(mode) }
                }
            }

            Divider()

            Text("Audio Output: \(audioOutputName)")
            Button("Switch to AirPods") { performAudioAction(switchToAirPods) }
            Button("Switch to Built-in") { performAudioAction(switchToBuiltIn) }
            Button("Toggle Audio Output") { performAudioAction(toggleAudioOutput) }
            if let audioError {
                Text("Audio error: \(audioError)")
                    .foregroundColor(.red)
            }

            Divider()

            // `openSettings`/`SettingsLink` need macOS 14+; this responder-chain
            // action is what SwiftUI's Settings scene has wired up since macOS 13.
            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")

            Button(updateChecker.isChecking ? "Checking for Updates…" : "Check for Updates…") {
                updateChecker.checkForUpdates()
            }
            .disabled(updateChecker.isChecking)

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear {
            permissions.refresh()
            refreshAudioStatus()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch noiseMode.status {
        case .idle(.some(let mode)):
            Text("Noise Mode: \(mode.displayName)")
        case .idle(nil):
            Text("Noise Mode: unknown (pick one below to sync)")
        case .transitioning(_, let to):
            Text("Switching to \(to.displayName)…")
        }
    }

    private var permissionsWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Permissions needed for Caps Lock control").bold()
            if permissions.accessibilityRequired && permissions.accessibility != .granted {
                Button("Grant Accessibility…") { permissions.requestAccessibility() }
            }
            if permissions.inputMonitoring != .granted {
                Button("Grant Input Monitoring…") { permissions.openInputMonitoringSettings() }
            }
        }
    }

    private func performAudioAction(_ action: () -> Result<AudioDeviceInfo, CoreError>) {
        switch action() {
        case .success:
            audioError = nil
        case .failure(let error):
            audioError = error.description
        }
        refreshAudioStatus()
    }

    private func refreshAudioStatus() {
        if let id = getDefaultOutputDevice(), let name = getDeviceName(id) {
            audioOutputName = name
        } else {
            audioOutputName = "—"
        }
    }
}
