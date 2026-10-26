import AirPodsCore
import CoreAudio
import Foundation

/// Reports when audio starts or stops playing through the AirPods, using the
/// output device's "running somewhere" flag. It stays true while any app has
/// the device open, so a paused player that releases the device reads as
/// stopped. Both edges are debounced, so a notification sound or a short gap
/// between tracks doesn't flip the mode.
@MainActor
final class PlaybackMonitor {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?

    private let playDelay: TimeInterval = 0.5
    private let pauseDelay: TimeInterval = 2.0

    private var deviceID: AudioDeviceID?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    /// What was last reported to the callbacks (or the state at attach time).
    private var reportedPlaying = false
    private var pending: DispatchWorkItem?

    func start() {
        guard devicesListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }
        }
        devicesListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        attach()
    }

    func stop() {
        detach()
        guard let block = devicesListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        devicesListener = nil
    }

    /// Follows the AirPods output device as it connects, disconnects or changes id.
    private func attach() {
        let current = findAudioDevices(matching: "AirPods").first?.id
        guard current != deviceID else { return }
        detach()
        guard let current else { return }

        var address = Self.runningAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.runningChanged() }
        }
        guard AudioObjectAddPropertyListenerBlock(current, &address, .main, block) == noErr else { return }
        deviceID = current
        runningListener = block
        // Start from the current state so connecting mid-song doesn't count as a press of play.
        reportedPlaying = Self.isRunning(current)
    }

    private func detach() {
        pending?.cancel()
        pending = nil
        if let id = deviceID, let block = runningListener {
            var address = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        deviceID = nil
        runningListener = nil
    }

    private func runningChanged() {
        guard let id = deviceID else { return }
        pending?.cancel()
        let running = Self.isRunning(id)
        guard running != reportedPlaying else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let id = self.deviceID,
                      Self.isRunning(id) == running, running != self.reportedPlaying
                else { return }
                self.reportedPlaying = running
                if running { self.onPlay?() } else { self.onPause?() }
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (running ? playDelay : pauseDelay), execute: item)
    }

    private static var runningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isRunning(_ device: AudioDeviceID) -> Bool {
        var address = runningAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }
}
