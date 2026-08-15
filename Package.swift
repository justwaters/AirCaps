// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirCaps",
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
            name: "aircaps",
            dependencies: ["AirPodsCore"]
        ),
        // Named "AirCapsApp" (not "AirCaps") to avoid colliding with the
        // "aircaps" CLI target's Sources/ folder on case-insensitive
        // filesystems (the default for macOS) — SPM derives each target's
        // source path from its name, and "AirCaps" vs "aircaps" would resolve
        // to the same path there. The Makefile renames the built binary to
        // "AirCaps" when assembling the .app bundle, so the app itself is
        // still named correctly.
        .executableTarget(
            name: "AirCapsApp",
            dependencies: ["AirPodsCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
