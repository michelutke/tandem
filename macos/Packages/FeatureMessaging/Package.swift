// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureMessaging",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureMessaging", targets: ["FeatureMessaging"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemTestSupport"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemStore")
    ],
    targets: [
        .target(
            name: "FeatureMessaging",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMessagingTests",
            dependencies: ["FeatureMessaging", "TandemTestSupport", "TandemProtocol", "TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
