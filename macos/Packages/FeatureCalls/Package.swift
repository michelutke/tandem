// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureCalls",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureCalls", targets: ["FeatureCalls"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemStore"),
        .package(path: "../TandemDesign"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureCalls",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemStore", "TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureCallsTests",
            dependencies: ["FeatureCalls", "TandemCrypto", "TandemProtocol", "TandemStore", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
