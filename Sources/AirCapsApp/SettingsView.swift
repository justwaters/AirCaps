import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionsGate
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Noise Mode") {
                Picker("When Caps Lock LED is off:", selection: $settings.offMode) {
                    ForEach(OffMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Permissions") {
                permissionRow("Accessibility", state: permissions.accessibility) {
                    permissions.requestAccessibility()
                }
                permissionRow("Input Monitoring", state: permissions.inputMonitoring) {
                    permissions.openInputMonitoringSettings()
                }
                Button("Re-check Permissions") { permissions.refresh() }
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { permissions.refresh() }
    }

    private func permissionRow(_ name: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            switch state {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .denied, .unknown:
                Button("Grant…", action: action)
            }
        }
    }
}
