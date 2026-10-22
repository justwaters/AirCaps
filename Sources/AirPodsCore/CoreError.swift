import Foundation

public enum CoreError: Error, CustomStringConvertible, Sendable {
    case noAirPodsAudioDevice
    case noBuiltInOutput
    case audioSwitchFailed
    case axNotTrusted
    case unknownNoiseMode(String)
    case controlCenterNotFound
    case soundItemNotFound
    case popoverTimeout
    case disclosureTriangleNotFound
    case checkboxNotFound(String)
    case backendFailed(String)

    public var description: String {
        switch self {
        case .backendFailed(let message): return message
        case .noAirPodsAudioDevice: return "No AirPods audio device found"
        case .noBuiltInOutput: return "No built-in output found"
        case .audioSwitchFailed: return "Failed to switch audio output"
        case .axNotTrusted: return "Accessibility permission required"
        case .unknownNoiseMode(let mode): return "Unknown noise mode: \(mode)"
        case .controlCenterNotFound: return "ControlCenter not found"
        case .soundItemNotFound: return "Could not find Sound menu bar item"
        case .popoverTimeout: return "Sound popover did not appear"
        case .disclosureTriangleNotFound: return "Could not find disclosure triangle (are AirPods connected?)"
        case .checkboxNotFound(let mode): return "Could not find '\(mode)' checkbox in popover"
        }
    }
}
