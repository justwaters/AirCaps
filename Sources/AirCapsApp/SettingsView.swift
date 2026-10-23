import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionsGate
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    Picker("When Caps Lock LED is off", selection: $settings.offMode) {
                        ForEach(OffMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Noise Mode")
                } footer: {
                    Text("LED on always means Noise Cancellation.")
                }

                Section {
                    Picker("Switch noise mode using", selection: $settings.backendChoice) {
                        ForEach(BackendChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Backend")
                } footer: {
                    Text("The CoreAudio backend uses an undocumented macOS API; switch to Control Center if it stops working.")
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

                Section {
                    permissionRow(
                        "Accessibility",
                        detail: permissions.accessibilityRequired ? nil : "Not needed with the CoreAudio backend",
                        state: permissions.accessibility
                    ) {
                        permissions.requestAccessibility()
                    }
                    permissionRow("Input Monitoring", detail: "Needed to capture Caps Lock", state: permissions.inputMonitoring) {
                        permissions.openInputMonitoringSettings()
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Button("Re-check Permissions") { permissions.refresh() }
                        .buttonStyle(.link)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420)
        .onAppear { permissions.refresh() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("AirCaps").font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func permissionRow(
        _ name: String, detail: String? = nil, state: PermissionState, action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let detail {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                }
            }
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
