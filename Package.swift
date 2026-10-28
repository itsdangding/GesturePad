// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GesturePad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GesturePad", targets: ["GesturePad"])
    ],
    targets: [
        .target(
            name: "GesturePadCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GesturePad",
            dependencies: ["GesturePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GesturePadCoreTests",
            dependencies: ["GesturePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
