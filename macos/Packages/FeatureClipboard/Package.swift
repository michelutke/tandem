// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureClipboard",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureClipboard", targets: ["FeatureClipboard"])
    ],
    dependencies: [
        .package(path: "../TandemTestSupport"),
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemTransport")
    ],
    targets: [
        .target(
            name: "FeatureClipboard",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemTransport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureClipboardTests",
            dependencies: [
                "FeatureClipboard", "TandemTestSupport", "TandemCrypto", "TandemProtocol", "TandemTransport"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
