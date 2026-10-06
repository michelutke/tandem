// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureFocus",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureFocus", targets: ["FeatureFocus"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemTransport"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureFocus",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemTransport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFocusTests",
            dependencies: ["FeatureFocus", "TandemCrypto", "TandemProtocol", "TandemTransport", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
