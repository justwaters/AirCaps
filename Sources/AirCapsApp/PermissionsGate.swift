import AirPodsCore
import AppKit
import IOKit.hid

public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
    case unknown
}

/// Tracks Accessibility (AX automation of Control Center) and Input Monitoring
/// (raw IOHIDManager access) permission state. Unlike Accessibility, macOS has
/// no OS-native "request" API for Input Monitoring — the only option is to
/// deep-link into System Settings and let the user grant it manually.
@MainActor
public final class PermissionsGate: ObservableObject {
    @Published public private(set) var accessibility: PermissionState = .unknown
    @Published public private(set) var inputMonitoring: PermissionState = .unknown

    /// Whether the active noise-control backend needs Accessibility. When false,
    /// Accessibility state is ignored for gating Caps Lock control.
    @Published public var accessibilityRequired = true

    public var allGranted: Bool {
        (!accessibilityRequired || accessibility == .granted) && inputMonitoring == .granted
    }

    public init() {
        refresh()
    }

    /// Re-check both permissions. Call on launch and every time the status-item
    /// menu opens — either grant can be revoked externally at any time.
    public func refresh() {
        accessibility = isAXTrusted() ? .granted : .denied
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: inputMonitoring = .granted
        case kIOHIDAccessTypeDenied: inputMonitoring = .denied
        default: inputMonitoring = .unknown
        }
    }

    public func requestAccessibility() {
        requestAXTrust()
    }

    public func openInputMonitoringSettings() {
        // macOS only lists an app in the Input Monitoring pane after it has
        // requested access, so ask first (no-op if already decided).
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    public func openAccessibilitySettings() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
