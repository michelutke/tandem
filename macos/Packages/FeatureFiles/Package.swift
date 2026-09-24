// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureFiles", targets: ["FeatureFiles"])
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFilesTests",
            dependencies: ["FeatureFiles"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
