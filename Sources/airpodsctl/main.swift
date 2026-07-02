import Foundation
import CoreAudio
import IOBluetooth
import AppKit
import ApplicationServices
import CoreGraphics

func printerr(_ msg: String) {
    fputs(msg + "\n", stderr)
}

// MARK: - Audio Device Management (CoreAudio)

struct AudioDeviceInfo {
    let id: AudioDeviceID
    let name: String
    let isOutput: Bool
}

func getAllAudioDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
    ) == noErr else { return [] }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices
    )
    return devices
}

func getDeviceName(_ id: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &name) == noErr
    else { return nil }
    return name?.takeUnretainedValue() as String?
}

func deviceHasOutput(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr
    else { return false }
    return dataSize > 0
}

func getDefaultOutputDevice() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var id = AudioDeviceID(0)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &id
    ) == noErr else { return nil }
    return id
}

func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = id
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
    ) == noErr
}

func setDefaultSystemOutputDevice(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = id
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
    ) == noErr
}

func findAudioDevices(matching nameSubstring: String) -> [AudioDeviceInfo] {
    let all: [AudioDeviceInfo] = getAllAudioDevices().compactMap { id in
        guard let name = getDeviceName(id) else { return nil }
        return AudioDeviceInfo(id: id, name: name, isOutput: deviceHasOutput(id))
    }
    return all.filter { $0.isOutput && $0.name.localizedCaseInsensitiveContains(nameSubstring) }
}

func findBuiltInOutput() -> AudioDeviceInfo? {
    let all: [AudioDeviceInfo] = getAllAudioDevices().compactMap { id in
        guard let name = getDeviceName(id) else { return nil }
        return AudioDeviceInfo(id: id, name: name, isOutput: deviceHasOutput(id))
    }
    let outputs = all.filter { $0.isOutput }
    return outputs.first { $0.name == "Built-in Output" }
        ?? outputs.first { $0.name == "MacBook Pro Speakers" }
        ?? outputs.first { $0.name.localizedCaseInsensitiveContains("built-in") }
        ?? outputs.first { $0.name.localizedCaseInsensitiveContains("speaker") && !$0.name.localizedCaseInsensitiveContains("airpods") }
}

// MARK: - Bluetooth Device Management (IOBluetooth)

func findAirPodsBluetoothDevice() -> IOBluetoothDevice? {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        return nil
    }
    let airPods = devices.filter { $0.name?.localizedCaseInsensitiveContains("AirPods") ?? false }
    let audioNames = findAudioDevices(matching: "AirPods").map { $0.name.lowercased() }
    let connected = airPods.filter { $0.isConnected() }
    for bt in connected {
        if let name = bt.name?.lowercased(), audioNames.contains(where: { $0.contains(name) || name.contains($0) }) {
            return bt
        }
    }
    return connected.first ?? airPods.first
}

func allBluetoothDevices() -> [(name: String, connected: Bool, paired: Bool)] {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        return []
    }
    return devices.map { ($0.name ?? "?", $0.isConnected(), $0.isPaired()) }
}

// MARK: - Battery Info (system_profiler)

func parseBatteryLevels() -> [(device: String, levels: [String: Int])] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    task.arguments = ["SPBluetoothDataType", "-detailLevel", "mini"]
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return parseBatteryFromProfiler(output)
}

func parseBatteryFromProfiler(_ text: String) -> [(device: String, levels: [String: Int])] {
    var results: [(device: String, levels: [String: Int])] = []
    var currentDevice: String?
    var currentLevels: [String: Int] = [:]
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Connected:") || trimmed.hasPrefix("Not Connected:") {
            flushDevice(&results, device: &currentDevice, levels: &currentLevels)
            currentDevice = nil
            currentLevels = [:]
            continue
        }
        if trimmed.hasSuffix(":") && !trimmed.contains(": ") {
            flushDevice(&results, device: &currentDevice, levels: &currentLevels)
            currentDevice = String(trimmed.dropLast())
            currentLevels = [:]
            continue
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, currentDevice != nil else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let val = parts[1].trimmingCharacters(in: .whitespaces)
        if key.hasSuffix("battery level"), let num = Int(val.dropLast()) {
            let name = key.replacingOccurrences(of: "battery level", with: "").trimmingCharacters(in: .whitespaces)
            currentLevels[name.isEmpty ? "combined" : name] = num
        }
    }
    flushDevice(&results, device: &currentDevice, levels: &currentLevels)
    return results
}

func flushDevice(_ results: inout [(device: String, levels: [String: Int])], device: inout String?, levels: inout [String: Int]) {
    if let dev = device, !levels.isEmpty {
        results.append((dev, levels))
    }
}

func consolidateBatteries(_ input: [(device: String, levels: [String: Int])]) -> [(device: String, levels: [String: Int])] {
    var merged: [String: [String: Int]] = [:]
    for (device, levels) in input {
        if let existing = merged[device] {
            var combined = existing
            for (key, val) in levels {
                combined[key] = val
            }
            merged[device] = combined
        } else {
            merged[device] = levels
        }
    }
    return merged.map { ($0.key, $0.value) }
}

func colorizedBatteryPercentage(_ val: Int) -> String {
    let reset = "\u{001B}[0m"
    if val <= 20 {
        let red = "\u{001B}[31m"
        return "\(red)\(val)%\(reset)"
    } else if val <= 80 {
        let yellow = "\u{001B}[33m"
        return "\(yellow)\(val)%\(reset)"
    } else {
        let green = "\u{001B}[32m"
        return "\(green)\(val)%\(reset)"
    }
}

// MARK: - Status

func showStatus() {
    let defaultID = getDefaultOutputDevice()
    let defaultName = defaultID.flatMap { getDeviceName($0) } ?? "?"
    let airPodsAudio = findAudioDevices(matching: "AirPods")
    let airPodsBT = findAirPodsBluetoothDevice()
    let builtIn = findBuiltInOutput()

    // ANSI Escape Codes for formatting
    let greenColor = "\u{001B}[32m"
    let redColor = "\u{001B}[31m"
    let resetColor = "\u{001B}[0m"

    print("Audio Output: \(defaultName)")
    if !airPodsAudio.isEmpty {
        let active = airPodsAudio.contains { $0.id == defaultID }
        let stateStr = active ? "active" : "available"
        // Wrap state in green brackets
        print("AirPods Audio: \(greenColor)[\(stateStr)]\(resetColor)")
        for d in airPodsAudio {
            print("  \(d.name)")
        }
    } else {
        print("AirPods Audio: \(redColor)not found\(resetColor)")
    }

    if let bt = airPodsBT {
        let connected = bt.isConnected()
        let stateStr = connected ? "connected" : "paired"
        // Wrap state in green brackets
        print("Bluetooth: \(greenColor)[\(stateStr)]\(resetColor) (\(bt.name ?? "?"))")
        print("  Address: \(bt.addressString ?? "?")")
    } else {
        print("Bluetooth: no AirPods paired")
    }

    let batteries = consolidateBatteries(parseBatteryLevels())
    for bat in batteries {
        if bat.device.localizedCaseInsensitiveContains("AirPods") {
            print("Battery:")
            for (key, val) in bat.levels {
                print("  \(key.capitalized): \(colorizedBatteryPercentage(val))")
            }
        }
    }

    if let builtIn {
        print("Built-in: \(builtIn.name)")
    }
}

// MARK: - Noise Control (Accessibility)

func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var val: CFTypeRef?
    AXUIElementCopyAttributeValue(el, attr as CFString, &val)
    return val
}

func axPress(_ el: AXUIElement) {
    AXUIElementPerformAction(el, kAXPressAction as CFString)
}

func axFind(_ el: AXUIElement, matching descOrTitle: String) -> AXUIElement? {
    let desc = axAttr(el, kAXDescriptionAttribute) as? String ?? ""
    let title = axAttr(el, kAXTitleAttribute) as? String ?? ""
    let combined = (desc + " " + title).trimmingCharacters(in: .whitespaces)
    if combined == descOrTitle || desc == descOrTitle || title == descOrTitle {
        return el
    }
    if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for kid in kids {
            if let found = axFind(kid, matching: descOrTitle) { return found }
        }
    }
    return nil
}

func axFindAll(_ el: AXUIElement, role: String) -> [AXUIElement] {
    let r = axAttr(el, kAXRoleAttribute) as? String ?? ""
    var results: [AXUIElement] = []
    if r == role { results.append(el) }
    if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for kid in kids { results += axFindAll(kid, role: role) }
    }
    return results
}

func ensureAXPermissions() {
    guard AXIsProcessTrusted() else {
        printerr("Accessibility permission required.")
        printerr("Grant it in System Settings → Privacy & Security → Accessibility, then re-run.")
        // Prompt the user
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        exit(1)
    }
}

let kNoiseModeNames = [
    "ANC": "Noise Cancellation",
    "AT": "Adaptive",
    "TR": "Transparency",
]

func runSetNoiseMode(_ shortName: String) {
    ensureAXPermissions()

    guard let targetMode = kNoiseModeNames[shortName] else {
        printerr("Unknown noise mode: \(shortName)")
        exit(1)
    }

    guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
        printerr("ControlCenter not found")
        exit(1)
    }

    let axApp = AXUIElementCreateApplication(cc.processIdentifier)

    guard let soundBtn = axFind(axApp, matching: "Sound") else {
        printerr("Could not find Sound menu bar item")
        exit(1)
    }

    axPress(soundBtn)

    var popoverWindow: AXUIElement?
    for _ in 0..<60 {
        Thread.sleep(forTimeInterval: 0.05)
        if let windows = axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement] {
            for w in windows {
                let subrole = axAttr(w, kAXSubroleAttribute) as? String ?? ""
                if subrole == "AXSystemDialog" {
                    popoverWindow = w
                    break
                }
            }
        }
        if popoverWindow != nil { break }
    }

    guard let window = popoverWindow else {
        printerr("Sound popover did not appear")
        exit(1)
    }

    let triangles = axFindAll(window, role: "AXDisclosureTriangle")
    guard let triangle = triangles.first else {
        printerr("Could not find disclosure triangle (are AirPods connected?)")
        exit(1)
    }

    let triVal = axAttr(triangle, kAXValueAttribute)
    let isExpanded: Bool
    if let b = triVal as? Bool { isExpanded = b }
    else if let i = triVal as? Int { isExpanded = i != 0 }
    else { isExpanded = false }

    if !isExpanded {
        axPress(triangle)
        Thread.sleep(forTimeInterval: 0.1)
    }

    guard let targetCheckbox = axFind(window, matching: targetMode) else {
        printerr("Could not find '\(targetMode)' checkbox in popover")
        exit(1)
    }

    axPress(targetCheckbox)
    Thread.sleep(forTimeInterval: 0.05)

    axPress(soundBtn)

    print("Noise mode set to \(shortName) (\(targetMode))")
}

// MARK: - Commands

func runOn() {
    guard let airPods = findAudioDevices(matching: "AirPods").first else {
        printerr("No AirPods audio device found")
        exit(1)
    }
    if setDefaultOutputDevice(airPods.id) {
        _ = setDefaultSystemOutputDevice(airPods.id)
        print("Switched audio output to \(airPods.name)")
    } else {
        printerr("Failed to switch audio output")
        exit(1)
    }
    if let bt = findAirPodsBluetoothDevice(), !bt.isConnected() {
        print("Connecting Bluetooth...")
        bt.openConnection()
    }
}

func runOff() {
    guard let builtIn = findBuiltInOutput() else {
        printerr("No built-in output found")
        print("Available outputs:")
        let list: [AudioDeviceInfo] = getAllAudioDevices().compactMap { id in
            guard let name = getDeviceName(id), deviceHasOutput(id) else { return nil }
            return AudioDeviceInfo(id: id, name: name, isOutput: true)
        }
        for d in list {
            print("  \(d.name)")
        }
        exit(1)
    }
    if setDefaultOutputDevice(builtIn.id) {
        _ = setDefaultSystemOutputDevice(builtIn.id)
        print("Switched audio output to \(builtIn.name)")
    } else {
        printerr("Failed to switch audio output")
        exit(1)
    }
}

func runToggle() {
    let defaultID = getDefaultOutputDevice()
    let defaultName = defaultID.flatMap { getDeviceName($0) } ?? "?"
    if defaultName.localizedCaseInsensitiveContains("AirPods") {
        runOff()
    } else {
        runOn()
    }
}

func runList() {
    print("=== Audio Devices ===")
    let audioList: [AudioDeviceInfo] = getAllAudioDevices().compactMap { id in
        guard let name = getDeviceName(id), deviceHasOutput(id) else { return nil }
        return AudioDeviceInfo(id: id, name: name, isOutput: true)
    }
    for d in audioList {
        print("  \(d.name)")
    }

    print("\n=== Bluetooth Devices ===")
    for d in allBluetoothDevices() {
        let state = d.connected ? "connected" : (d.paired ? "paired" : "unpaired")
        print("  \(d.name) (\(state))")
    }

    let batteries = consolidateBatteries(parseBatteryLevels())
    if !batteries.isEmpty {
        print("\n=== Battery Levels ===")
        for bat in batteries {
            print("  \(bat.device):")
            for (key, val) in bat.levels {
                print("    \(key.capitalized): \(colorizedBatteryPercentage(val))")
            }
        }
    }
}

func printUsage() {
    print("Usage: airpodsctl [command]")
    print()
    print("Commands:")
    print("  status          Show AirPods connection and audio status (default)")
    print("  on              Switch audio output to AirPods")
    print("  off             Switch audio output to built-in speakers")
    print("  toggle          Toggle between AirPods and built-in speakers")
    print("  list            List all audio devices and Bluetooth devices")
    print("  ANC             Set noise control to Active Noise Cancellation")
    print("  AT              Set noise control to Adaptive Transparency")
    print("  TR              Set noise control to Transparency")
}

// MARK: - Main

let command = CommandLine.arguments.dropFirst().first ?? "status"
switch command.uppercased() {
case "STATUS": showStatus()
case "ON": runOn()
case "OFF": runOff()
case "TOGGLE": runToggle()
case "LIST": runList()
case "ANC", "AT", "TR": runSetNoiseMode(command.uppercased())
case "-H", "--HELP", "HELP": printUsage()
default:
    printerr("Unknown command: \(command)")
    printUsage()
    exit(1)
}
