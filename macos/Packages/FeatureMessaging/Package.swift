// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureMessaging",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureMessaging", targets: ["FeatureMessaging"])
    ],
    targets: [
        .target(
            name: "FeatureMessaging",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMessagingTests",
            dependencies: ["FeatureMessaging"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
