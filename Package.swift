// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Relay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RelayCore", targets: ["RelayCore"]),
        .executable(name: "RelayApp", targets: ["RelayApp"]),
        .executable(name: "RelayHelper", targets: ["RelayHelper"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "RelayCore",
            dependencies: ["CSQLite"],
            path: "Sources/RelayCore"
        ),
        .executableTarget(
            name: "RelayApp",
            dependencies: ["RelayCore"],
            path: "Sources/RelayApp"
        ),
        .executableTarget(
            name: "RelayHelper",
            dependencies: ["RelayCore"],
            path: "Sources/RelayHelper"
        ),
        .testTarget(
            name: "RelayCoreTests",
            dependencies: ["RelayCore"],
            path: "Tests/RelayCoreTests"
        )
    ]
)
