// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureMedia",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureMedia", targets: ["FeatureMedia"])
    ],
    dependencies: [
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemDesign"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureMedia",
            dependencies: ["TandemProtocol", "TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMediaTests",
            dependencies: ["FeatureMedia", "TandemProtocol", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
