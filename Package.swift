// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pier",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PierCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Pier",
            dependencies: ["PierCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PierIcon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PierCoreTests",
            dependencies: ["PierCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
