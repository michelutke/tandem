// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureFiles", targets: ["FeatureFiles"])
    ],
    dependencies: [
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemStore"),
        .package(path: "../TandemTestSupport"),
        .package(path: "../TandemDesign")
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            dependencies: ["TandemProtocol", "TandemCrypto", "TandemStore", "TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFilesTests",
            dependencies: ["FeatureFiles", "TandemProtocol", "TandemCrypto", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
