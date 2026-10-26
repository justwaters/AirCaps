import AirPodsCore
import CoreAudio
import Foundation

/// Reports when audio starts or stops playing through the AirPods, using the
/// output device's "running somewhere" flag. It stays true while any app has
/// the device open, so a paused player that releases the device reads as
/// stopped, but apps can take several seconds to let go. Music and Spotify also
/// announce play and pause right away, which is used as a faster signal while the
/// AirPods are the output. Both edges are debounced, so a notification sound or
/// a short gap between tracks doesn't flip the mode.
@MainActor
final class PlaybackMonitor {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?

    private let playDelay: TimeInterval = 0.3
    private let pauseDelay: TimeInterval = 1.0

    private var deviceID: AudioDeviceID?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    /// What was last reported to the callbacks (or the state at attach time).
    private var reportedPlaying = false
    private var pending: DispatchWorkItem?
    private var playerObservers: [NSObjectProtocol] = []

    /// Notification name and the userInfo key holding "Playing" / "Paused" / "Stopped".
    private static let players: [(name: String, stateKey: String)] = [
        ("com.apple.Music.playerInfo", "Player State"),
        ("com.spotify.client.PlaybackStateChanged", "Player State"),
    ]
    private let playerDelay: TimeInterval = 0.2

    private func observePlayers() {
        for player in Self.players {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(player.name), object: nil, queue: .main
            ) { [weak self] note in
                let state = note.userInfo?[player.stateKey] as? String
                MainActor.assumeIsolated { self?.playerChanged(state: state) }
            }
            playerObservers.append(token)
        }
    }

    /// Only counts while the AirPods are where the sound goes, so a player
    /// pausing on the speakers doesn't change the AirPods' mode.
    private func playerChanged(state: String?) {
        guard let state, deviceID != nil, let output = getDefaultOutputDevice(), output == deviceID else { return }
        schedule(playing: state == "Playing", after: playerDelay) { [weak self] in
            // Still the same state a moment later, and AirPods still the output.
            self?.deviceID != nil && getDefaultOutputDevice() == self?.deviceID
        }
    }

    private func schedule(playing: Bool, after delay: TimeInterval, stillValid: @escaping @MainActor () -> Bool) {
        pending?.cancel()
        guard playing != reportedPlaying else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, stillValid(), playing != self.reportedPlaying else { return }
                self.reportedPlaying = playing
                if playing { self.onPlay?() } else { self.onPause?() }
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func start() {
        guard devicesListener == nil else { return }
        observePlayers()
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
        for token in playerObservers { DistributedNotificationCenter.default().removeObserver(token) }
        playerObservers = []
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
        let running = Self.isRunning(id)
        schedule(playing: running, after: running ? playDelay : pauseDelay) { [weak self] in
            guard let id = self?.deviceID else { return false }
            return Self.isRunning(id) == running
        }
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
