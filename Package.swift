// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirpodsCTL",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AirPodsCore",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .executableTarget(
            name: "airpodsctl",
            dependencies: ["AirPodsCore"]
        ),
        // Named "AirpodsCTLApp" (not "AirpodsCTL") to avoid colliding with the
        // "airpodsctl" CLI target's Sources/ folder on case-insensitive
        // filesystems (the default for macOS) — SPM derives each target's
        // source path from its name, and "AirpodsCTL" vs "airpodsctl" resolve
        // to the same path there. The Makefile renames the built binary to
        // "AirpodsCTL" when assembling the .app bundle, so the app itself is
        // still named correctly.
        .executableTarget(
            name: "AirpodsCTLApp",
            dependencies: ["AirPodsCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
