// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShowMyBest",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ShowMyBestKit",
            path: "Sources/ShowMyBestKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ShowMyBest",
            dependencies: ["ShowMyBestKit"],
            path: "Sources/ShowMyBest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["ShowMyBestKit"],
            path: "Sources/SelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
