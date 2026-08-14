import CoreAudio

public struct AudioDeviceInfo: Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let isOutput: Bool

    public init(id: AudioDeviceID, name: String, isOutput: Bool) {
        self.id = id
        self.name = name
        self.isOutput = isOutput
    }
}

public func getAllAudioDevices() -> [AudioDeviceID] {
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

public func getDeviceName(_ id: AudioDeviceID) -> String? {
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

public func deviceHasOutput(_ id: AudioDeviceID) -> Bool {
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

public func getDefaultOutputDevice() -> AudioDeviceID? {
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

public func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
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

public func setDefaultSystemOutputDevice(_ id: AudioDeviceID) -> Bool {
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

public func findAudioDevices(matching nameSubstring: String) -> [AudioDeviceInfo] {
    let all: [AudioDeviceInfo] = getAllAudioDevices().compactMap { id in
        guard let name = getDeviceName(id) else { return nil }
        return AudioDeviceInfo(id: id, name: name, isOutput: deviceHasOutput(id))
    }
    return all.filter { $0.isOutput && $0.name.localizedCaseInsensitiveContains(nameSubstring) }
}

public func findBuiltInOutput() -> AudioDeviceInfo? {
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

// MARK: - Orchestration (shared by CLI and menu-bar app)

@discardableResult
public func switchToAirPods() -> Result<AudioDeviceInfo, CoreError> {
    guard let airPods = findAudioDevices(matching: "AirPods").first else {
        return .failure(.noAirPodsAudioDevice)
    }
    guard setDefaultOutputDevice(airPods.id) else {
        return .failure(.audioSwitchFailed)
    }
    _ = setDefaultSystemOutputDevice(airPods.id)
    return .success(airPods)
}

@discardableResult
public func switchToBuiltIn() -> Result<AudioDeviceInfo, CoreError> {
    guard let builtIn = findBuiltInOutput() else {
        return .failure(.noBuiltInOutput)
    }
    guard setDefaultOutputDevice(builtIn.id) else {
        return .failure(.audioSwitchFailed)
    }
    _ = setDefaultSystemOutputDevice(builtIn.id)
    return .success(builtIn)
}

@discardableResult
public func toggleAudioOutput() -> Result<AudioDeviceInfo, CoreError> {
    let defaultID = getDefaultOutputDevice()
    let defaultName = defaultID.flatMap { getDeviceName($0) } ?? ""
    if defaultName.localizedCaseInsensitiveContains("AirPods") {
        return switchToBuiltIn()
    } else {
        return switchToAirPods()
    }
}
