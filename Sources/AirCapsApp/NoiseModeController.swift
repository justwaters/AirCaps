import AirPodsCore
import CoreAudio
import Foundation

public enum NoiseMode: String, Sendable, CaseIterable {
    case noiseCancellation = "ANC"
    case adaptive = "AT"
    case transparency = "TR"

    /// LED on = Noise Cancellation, LED off = whichever off-mode is configured.
    var isLEDOn: Bool { self == .noiseCancellation }

    var displayName: String { AirPodsCore.kNoiseModeNames[rawValue] ?? rawValue }
}

public enum ControllerStatus: Sendable, Equatable {
    /// `nil` mode = not yet known — there's no cheap way to read AirPods' current
    /// mode without going through the same AX popover flow used to set it, so the
    /// app doesn't know the real state until the first transition happens.
    case idle(NoiseMode?)
    /// No AirPods audio device is connected.
    case disconnected
    case transitioning(from: NoiseMode?, to: NoiseMode)
}

/// Debounces physical Caps Lock presses (and manual menu selections) into
/// AirPods noise-mode changes: only one AX-automation run (which takes real
/// wall-clock time, up to a few seconds) is in flight at a time. Presses that
/// land mid-transition are simply dropped, not queued. Runs entirely on the
/// main actor, which is what actually guarantees exclusivity here — every
/// entry point (Caps Lock callback, manual menu action) is already
/// main-actor-isolated, so there's a single serialized owner of `status`.
@MainActor
public final class NoiseModeController: ObservableObject {
    @Published public private(set) var status: ControllerStatus = .idle(nil)
    @Published public private(set) var lastError: String?

    private let capsLock: CapsLockController
    private let offMode: () -> NoiseMode
    private var lastTransitionEnd = Date.distantPast
    private let debounceInterval: TimeInterval = 0.3

    private let backend: () -> any NoiseControlBackend

    public init(
        capsLock: CapsLockController,
        offMode: @escaping () -> NoiseMode,
        backend: @escaping () -> any NoiseControlBackend = { AXControlCenterBackend() }
    ) {
        self.capsLock = capsLock
        self.offMode = offMode
        self.backend = backend
        capsLock.onCapsLockPressed = { [weak self] in
            self?.handleCapsLockPressed()
        }
        refreshFromDevice()
        observeAudioDevices()
    }

    /// Syncs `status` (and the Caps Lock LED) with what the AirPods report.
    /// Reading the mode goes through the CoreAudio property regardless of the
    /// selected backend, since it needs no permission. Skipped mid-transition.
    public func refreshFromDevice() {
        if case .transitioning = status { return }
        guard HALListeningModeBackend.isAirPodsConnected() else {
            status = .disconnected
            capsLock.setLEDState(.off)
            return
        }
        let mode = HALListeningModeBackend.currentShortName().flatMap(NoiseMode.init(rawValue:))
        status = .idle(mode)
        if let mode { capsLock.setLEDState(mode.isLEDOn ? .on : .off) }
    }

    private func observeAudioDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main
        ) { [weak self] _, _ in
            // The device list changes before the AirPods' properties settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self?.refreshFromDevice() }
            }
        }
    }

    public func handleCapsLockPressed() {
        refreshFromDevice()
        guard case .idle(let current) = status else { return }
        guard Date().timeIntervalSince(lastTransitionEnd) > debounceInterval else { return }
        let target: NoiseMode = (current == .noiseCancellation) ? offMode() : .noiseCancellation
        beginTransition(to: target, from: current)
    }

    /// Manual mode change (menu action) — same debounce/failure handling as Caps Lock.
    public func requestMode(_ target: NoiseMode) {
        refreshFromDevice()
        guard case .idle(let current) = status else { return }
        beginTransition(to: target, from: current)
    }

    /// Playback-driven change. Quietly does nothing if a change is in flight, the
    /// AirPods are away, or they are already where they should be. `ifCurrently`
    /// limits it to a source mode, so pausing doesn't override a hand-picked
    /// Transparency or Adaptive.
    public func autoSwitch(to target: NoiseMode, ifCurrently source: NoiseMode? = nil) {
        refreshFromDevice()
        guard case .idle(let current) = status, current != target else { return }
        if let source, let current, current != source { return }
        beginTransition(to: target, from: current)
    }

    private func beginTransition(to target: NoiseMode, from current: NoiseMode?) {
        status = .transitioning(from: current, to: target)
        lastError = nil
        // LED intentionally holds the last confirmed state until the transition commits.

        let backend = backend()
        Task {
            let result = backend.setMode(target.rawValue)
            self.finish(result: result, current: current, target: target)
        }
    }

    private func finish(result: Result<String, CoreError>, current: NoiseMode?, target: NoiseMode) {
        lastTransitionEnd = Date()
        switch result {
        case .success:
            status = .idle(target)
            capsLock.setLEDState(target.isLEDOn ? .on : .off)
        case .failure(let error):
            status = .idle(current)
            if let current {
                capsLock.setLEDState(current.isLEDOn ? .on : .off)
            }
            lastError = error.description
        }
    }
}
