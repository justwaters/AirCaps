import Foundation
import IOBluetooth
import AirPodsCore

func printerr(_ msg: String) {
    fputs(msg + "\n", stderr)
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

// MARK: - Accessibility

func ensureAXPermissions() {
    guard isAXTrusted() else {
        printerr("Accessibility permission required.")
        printerr("Grant it in System Settings → Privacy & Security → Accessibility, then re-run.")
        // Prompt the user
        requestAXTrust()
        exit(1)
    }
}

// MARK: - Commands

func runOn() {
    switch switchToAirPods() {
    case .success(let airPods):
        print("Switched audio output to \(airPods.name)")
    case .failure(.noAirPodsAudioDevice):
        printerr("No AirPods audio device found")
        exit(1)
    case .failure(.audioSwitchFailed):
        printerr("Failed to switch audio output")
        exit(1)
    case .failure(let e):
        printerr(e.description)
        exit(1)
    }
    if let bt = findAirPodsBluetoothDevice(), !bt.isConnected() {
        print("Connecting Bluetooth...")
        bt.openConnection()
    }
}

func runOff() {
    switch switchToBuiltIn() {
    case .success(let builtIn):
        print("Switched audio output to \(builtIn.name)")
    case .failure(.noBuiltInOutput):
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
    case .failure(.audioSwitchFailed):
        printerr("Failed to switch audio output")
        exit(1)
    case .failure(let e):
        printerr(e.description)
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

func runSetNoiseMode(_ shortName: String, backend: any NoiseControlBackend) {
    if backend.requiresAccessibility { ensureAXPermissions() }

    switch backend.setMode(shortName) {
    case .success(let targetMode):
        print("Noise mode set to \(shortName) (\(targetMode))")
    case .failure(.unknownNoiseMode(let mode)):
        printerr("Unknown noise mode: \(mode)")
        exit(1)
    case .failure(.controlCenterNotFound):
        printerr("ControlCenter not found")
        exit(1)
    case .failure(.soundItemNotFound):
        printerr("Could not find Sound menu bar item")
        exit(1)
    case .failure(.popoverTimeout):
        printerr("Sound popover did not appear")
        exit(1)
    case .failure(.disclosureTriangleNotFound):
        printerr("Could not find disclosure triangle (are AirPods connected?)")
        exit(1)
    case .failure(.checkboxNotFound(let mode)):
        printerr("Could not find '\(mode)' checkbox in popover")
        exit(1)
    case .failure(let e):
        printerr(e.description)
        exit(1)
    }
}

func printUsage() {
    print("Usage: aircaps [command]")
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
    print()
    print("Options (noise control commands):")
    print("  --backend ax|hal   ax: Control Center via Accessibility (default)")
    print("                     hal: CoreAudio private property, no Accessibility needed")
}

// MARK: - Main

let command = CommandLine.arguments.dropFirst().first ?? "status"
switch command.uppercased() {
case "STATUS": showStatus()
case "ON": runOn()
case "OFF": runOff()
case "TOGGLE": runToggle()
case "LIST": runList()
case "ANC", "AT", "TR":
    var backend: any NoiseControlBackend = AXControlCenterBackend()
    let args = Array(CommandLine.arguments.dropFirst(2))
    if let i = args.firstIndex(of: "--backend") {
        switch args.dropFirst(i + 1).first?.lowercased() {
        case "ax": break
        case "hal": backend = HALListeningModeBackend()
        default:
            printerr("--backend must be 'ax' or 'hal'")
            exit(1)
        }
    }
    runSetNoiseMode(command.uppercased(), backend: backend)
case "-H", "--HELP", "HELP": printUsage()
default:
    printerr("Unknown command: \(command)")
    printUsage()
    exit(1)
}
