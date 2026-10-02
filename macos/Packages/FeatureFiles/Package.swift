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
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            dependencies: ["TandemProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFilesTests",
            dependencies: ["FeatureFiles", "TandemProtocol", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
