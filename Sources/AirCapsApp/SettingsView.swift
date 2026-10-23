import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionsGate
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            section("Noise Mode", footer: "LED on always means Noise Cancellation.") {
                HStack {
                    Text("When Caps Lock LED is off")
                    Spacer()
                    Picker("", selection: $settings.offMode) {
                        ForEach(OffMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(10)
            }

            section(
                "Backend",
                footer: "The CoreAudio backend uses an undocumented macOS API; switch to Control Center if it stops working."
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch noise mode using")
                    Picker("", selection: $settings.backendChoice) {
                        ForEach(BackendChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }

            section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
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

            section("Permissions") {
                VStack(spacing: 0) {
                    permissionRow(
                        "Accessibility",
                        detail: permissions.accessibilityRequired ? nil : "Not needed with the CoreAudio backend",
                        state: permissions.accessibility
                    ) {
                        permissions.requestAccessibility()
                    }
                    Divider()
                    permissionRow("Input Monitoring", detail: "Needed to capture Caps Lock", state: permissions.inputMonitoring) {
                        permissions.openInputMonitoringSettings()
                    }
                }
            }

            Button("Re-check Permissions") { permissions.refresh() }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: true)
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
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Titled card with an optional right-aligned footnote underneath.
    private func section<Content: View>(
        _ title: String, footer: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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
        .padding(10)
    }
}
