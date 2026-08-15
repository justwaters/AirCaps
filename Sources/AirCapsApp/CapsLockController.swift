import AppKit
import Foundation
import IOKit.hid

/// Repurposes the physical Caps Lock key as a hardware toggle: suppresses the
/// OS's own Caps Lock behavior (text-input lock + auto-driven LED) system-wide
/// via `hidutil`, observes raw physical key-down transitions independently via
/// `IOHIDManager`, and owns the LED state explicitly across every connected
/// keyboard (built-in + any Magic Keyboards, USB or Bluetooth).
///
/// Validated empirically (see plan doc / smoke test) before this was written:
/// the raw `IOHIDManager` input callback keeps firing for Caps Lock even after
/// the `hidutil` remap is applied, and `IOHIDDeviceSetValue` succeeds on the
/// LED element without seizing the device.
@MainActor
public final class CapsLockController {
    private static let pageGenericDesktop: UInt32 = 0x01
    private static let usageKeyboard: UInt32 = 0x06
    private static let pageKeyboard: UInt32 = 0x07
    private static let usageCapsLock: UInt32 = 0x39
    private static let pageLEDs: UInt32 = 0x08
    private static let usageLEDCapsLock: UInt32 = 0x02
    private static let remapJSON = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000000}]}"#
    private static let clearRemapJSON = #"{"UserKeyMapping":[]}"#

    public enum LEDState {
        case on
        case off

        var intValue: CFIndex { self == .on ? 1 : 0 }
    }

    /// Called on the main actor when a physical Caps Lock key-down is observed.
    public var onCapsLockPressed: (() -> Void)?

    private let manager: IOHIDManager
    private var currentLEDState: LEDState = .off
    private var isRunning = false
    private var wakeObserver: NSObjectProtocol?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        resetAndApplyRemap()

        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: Self.pageGenericDesktop,
            kIOHIDDeviceUsageKey as String: Self.usageKeyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchingCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applyRemap()
                self.applyLED(to: self.currentDevices(), state: self.currentLEDState)
            }
        }
    }

    /// Reverts the Caps Lock remap so normal OS behavior resumes. Call on
    /// clean quit (`applicationWillTerminate`) — a crash is safe too since
    /// `hidutil` remaps reset on reboot, but a clean quit without this would
    /// leave Caps Lock dead system-wide until the next reboot.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        revertRemap()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Sets the Caps Lock LED on every currently connected keyboard.
    public func setLEDState(_ state: LEDState) {
        currentLEDState = state
        applyLED(to: currentDevices(), state: state)
    }

    // MARK: - Devices / LED

    private func currentDevices() -> [IOHIDDevice] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
    }

    private func applyLED(to devices: [IOHIDDevice], state: LEDState) {
        for device in devices {
            let matchDict: [String: Any] = [
                kIOHIDElementUsagePageKey as String: Self.pageLEDs,
                kIOHIDElementUsageKey as String: Self.usageLEDCapsLock,
            ]
            guard let elements = IOHIDDeviceCopyMatchingElements(device, matchDict as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement],
                  let ledElement = elements.first else { continue }
            let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, ledElement, 0, state.intValue)
            IOHIDDeviceSetValue(device, ledElement, value)
        }
    }

    // MARK: - hidutil remap lifecycle

    private func resetAndApplyRemap() {
        // Clear first: guards against a prior crash leaving a stale/stacked mapping.
        runHidutil(Self.clearRemapJSON)
        runHidutil(Self.remapJSON)
    }

    private func applyRemap() {
        runHidutil(Self.remapJSON)
    }

    private func revertRemap() {
        runHidutil(Self.clearRemapJSON)
    }

    private func runHidutil(_ propertyJSON: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", propertyJSON]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - C callbacks (must not capture `self` — routed via context pointer)

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let controller = Unmanaged<CapsLockController>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == CapsLockController.pageKeyboard,
              IOHIDElementGetUsage(element) == CapsLockController.usageCapsLock,
              IOHIDValueGetIntegerValue(value) == 1 else { return }
        Task { @MainActor in
            controller.onCapsLockPressed?()
        }
    }

    private static let deviceMatchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let controller = Unmanaged<CapsLockController>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in
            // Newly connected keyboards (e.g. a Magic Keyboard powering on)
            // need the remap re-applied and their LED synced to current state.
            controller.applyRemap()
            controller.applyLED(to: [device], state: controller.currentLEDState)
        }
    }
}
