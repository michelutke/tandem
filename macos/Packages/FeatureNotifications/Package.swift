// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureNotifications",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureNotifications", targets: ["FeatureNotifications"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemTestSupport"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemStore")
    ],
    targets: [
        .target(
            name: "FeatureNotifications",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureNotificationsTests",
            dependencies: ["FeatureNotifications", "TandemTestSupport", "TandemProtocol", "TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
