import CoreAudio
import Foundation

/// Sets the AirPods listening mode by writing the private CoreAudio HAL
/// property `'lstm'` on the AirPods Bluetooth audio device. Needs no
/// Accessibility permission. Undocumented; technique taken from
/// https://github.com/raulgg/pods-control (MIT).
public struct HALListeningModeBackend: NoiseControlBackend {
    public var requiresAccessibility: Bool { false }

    /// 'lstm' — private listening-mode selector.
    private static let listeningModeSelector = AudioObjectPropertySelector(0x6C73_746D)

    /// Short code -> raw HAL value (1 = off, 2 = ANC, 3 = transparency, 4 = adaptive).
    private static let rawValues: [String: UInt32] = ["ANC": 2, "TR": 3, "AT": 4]

    public init() {}

    public func setMode(_ shortName: String) -> Result<String, CoreError> {
        guard let name = kNoiseModeNames[shortName], let raw = Self.rawValues[shortName] else {
            return .failure(.unknownNoiseMode(shortName))
        }
        guard let device = findAudioDevices(matching: "AirPods").first else {
            return .failure(.noAirPodsAudioDevice)
        }

        // Try each scope the property might live on; use the first one the device exposes.
        let scopes = [kAudioObjectPropertyScopeGlobal, kAudioDevicePropertyScopeOutput]
        guard let address = scopes
            .map({ AudioObjectPropertyAddress(
                mSelector: Self.listeningModeSelector,
                mScope: $0,
                mElement: kAudioObjectPropertyElementMain) })
            .first(where: { var a = $0; return AudioObjectHasProperty(device.id, &a) })
        else {
            return .failure(.backendFailed("AirPods do not expose a listening-mode property"))
        }

        var addr = address
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device.id, &addr, &settable) == noErr, settable.boolValue else {
            return .failure(.backendFailed("Listening-mode property is not settable"))
        }

        var value = raw
        let status = AudioObjectSetPropertyData(device.id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            return .failure(.backendFailed("Setting listening mode failed (OSStatus \(status))"))
        }

        // Confirm the OS reports the new state. Spin the run loop rather than
        // sleeping so CoreAudio notifications can be delivered.
        for _ in 0..<16 {
            if Self.read(device.id, &addr) == raw { return .success(name) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return .failure(.backendFailed("Listening mode did not change to \(name)"))
    }

    private static func read(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
