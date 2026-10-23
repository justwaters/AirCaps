import Foundation

/// A way of switching AirPods noise mode. `shortName` is "ANC", "AT" or "TR".
/// On success returns the human-readable mode name.
public protocol NoiseControlBackend: Sendable {
    var requiresAccessibility: Bool { get }
    func setMode(_ shortName: String) -> Result<String, CoreError>
}

/// Drives Control Center's Sound popover through the Accessibility API.
public struct AXControlCenterBackend: NoiseControlBackend {
    public var requiresAccessibility: Bool { true }

    public init() {}

    public func setMode(_ shortName: String) -> Result<String, CoreError> {
        setNoiseMode(shortName)
    }
}
