// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureCalls",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureCalls", targets: ["FeatureCalls"])
    ],
    targets: [
        .target(
            name: "FeatureCalls",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureCallsTests",
            dependencies: ["FeatureCalls"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
