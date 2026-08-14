import IOBluetooth

public func findAirPodsBluetoothDevice() -> IOBluetoothDevice? {
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

public func allBluetoothDevices() -> [(name: String, connected: Bool, paired: Bool)] {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        return []
    }
    return devices.map { ($0.name ?? "?", $0.isConnected(), $0.isPaired()) }
}
