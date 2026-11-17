// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GTA6Altyazi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GTA6Altyazi", targets: ["GTA6Altyazi"])
    ],
    targets: [
        .executableTarget(
            name: "GTA6Altyazi",
            path: "Sources/GTA6Altyazi",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Network")
            ]
        )
    ]
)
