// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureMirror",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureMirror", targets: ["FeatureMirror"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemTransport"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureMirror",
            dependencies: ["TandemCrypto", "TandemProtocol", "TandemTransport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMirrorTests",
            dependencies: ["FeatureMirror", "TandemCrypto", "TandemProtocol", "TandemTransport", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
