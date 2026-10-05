// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureFocus",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureFocus", targets: ["FeatureFocus"])
    ],
    dependencies: [
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureFocus",
            dependencies: ["TandemProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFocusTests",
            dependencies: ["FeatureFocus", "TandemProtocol", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
