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
    /// Shared with `@AppStorage` in the app scene and the Settings view.
    public static let showMenuBarIconKey = "showMenuBarIcon"

    private enum Keys {
        static let offMode = "offMode"
        static let backend = "backend"
        static let switchOnPause = "switchOnPause"
        static let switchOnPlay = "switchOnPlay"
    }

    /// When audio stops on the AirPods, switch to the off-mode (Adaptive/Transparency).
    @Published public var switchOnPause: Bool {
        didSet { UserDefaults.standard.set(switchOnPause, forKey: Keys.switchOnPause) }
    }

    /// When audio starts on the AirPods, switch to Noise Cancellation.
    @Published public var switchOnPlay: Bool {
        didSet { UserDefaults.standard.set(switchOnPlay, forKey: Keys.switchOnPlay) }
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
        switchOnPause = UserDefaults.standard.bool(forKey: Keys.switchOnPause)
        switchOnPlay = UserDefaults.standard.bool(forKey: Keys.switchOnPlay)
        let stored = UserDefaults.standard.string(forKey: Keys.offMode)
        offMode = stored.flatMap(OffMode.init(rawValue:)) ?? .adaptive
        backendChoice = UserDefaults.standard.string(forKey: Keys.backend)
            .flatMap(BackendChoice.init(rawValue:)) ?? .hal
    }
}
