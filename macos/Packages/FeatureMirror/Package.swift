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
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureMirror",
            dependencies: ["TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMirrorTests",
            dependencies: ["FeatureMirror", "TandemCrypto", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
