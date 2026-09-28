// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureClipboard",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureClipboard", targets: ["FeatureClipboard"])
    ],
    dependencies: [
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureClipboard",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureClipboardTests",
            dependencies: ["FeatureClipboard", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
