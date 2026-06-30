// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "airpodsctl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "airpodsctl",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
            ]
        )
    ]
)
