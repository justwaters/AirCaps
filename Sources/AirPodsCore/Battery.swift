import Foundation

public func parseBatteryLevels() -> [(device: String, levels: [String: Int])] {
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

public func parseBatteryFromProfiler(_ text: String) -> [(device: String, levels: [String: Int])] {
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

public func consolidateBatteries(_ input: [(device: String, levels: [String: Int])]) -> [(device: String, levels: [String: Int])] {
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
