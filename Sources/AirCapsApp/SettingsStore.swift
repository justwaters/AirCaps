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

@MainActor
public final class SettingsStore: ObservableObject {
    private enum Keys {
        static let offMode = "offMode"
    }

    @Published public var offMode: OffMode {
        didSet {
            UserDefaults.standard.set(offMode.rawValue, forKey: Keys.offMode)
        }
    }

    public init() {
        let stored = UserDefaults.standard.string(forKey: Keys.offMode)
        offMode = stored.flatMap(OffMode.init(rawValue:)) ?? .adaptive
    }
}
