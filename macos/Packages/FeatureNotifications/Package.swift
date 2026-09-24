// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureNotifications",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureNotifications", targets: ["FeatureNotifications"])
    ],
    targets: [
        .target(
            name: "FeatureNotifications",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureNotificationsTests",
            dependencies: ["FeatureNotifications"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
