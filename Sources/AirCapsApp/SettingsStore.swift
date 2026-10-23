import AirPodsCore
import Foundation

/// The two modes the Caps Lock LED can represent when *off* (LED on always
/// means Noise Cancellation). Deliberately its own type rather than reusing
/// `NoiseMode` directly — `.noiseCancellation` is never a valid off-mode.
public enum OffMode: String, CaseIterable, Sendable {
    case adaptive = "AT"
    case transparency = "TR"

    public var displayName: String { AirPodsCore.kNoiseModeNames[rawValue] ?? rawValue }
    public var asNoiseMode: NoiseMode { NoiseMode(rawValue: rawValue)! }
}

/// How noise mode is switched. HAL needs no Accessibility permission.
public enum BackendChoice: String, CaseIterable, Sendable {
    case hal
    case accessibility

    public var displayName: String {
        switch self {
        case .hal: return "CoreAudio (no Accessibility needed)"
        case .accessibility: return "Control Center (Accessibility)"
        }
    }

    public var backend: any NoiseControlBackend {
        switch self {
        case .hal: return HALListeningModeBackend()
        case .accessibility: return AXControlCenterBackend()
        }
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    private enum Keys {
        static let offMode = "offMode"
        static let backend = "backend"
    }

    @Published public var backendChoice: BackendChoice {
        didSet {
            UserDefaults.standard.set(backendChoice.rawValue, forKey: Keys.backend)
        }
    }

    @Published public var offMode: OffMode {
        didSet {
            UserDefaults.standard.set(offMode.rawValue, forKey: Keys.offMode)
        }
    }

    public init() {
        let stored = UserDefaults.standard.string(forKey: Keys.offMode)
        offMode = stored.flatMap(OffMode.init(rawValue:)) ?? .adaptive
        backendChoice = UserDefaults.standard.string(forKey: Keys.backend)
            .flatMap(BackendChoice.init(rawValue:)) ?? .hal
    }
}
