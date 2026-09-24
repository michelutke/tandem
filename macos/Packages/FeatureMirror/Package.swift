// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureMirror",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureMirror", targets: ["FeatureMirror"])
    ],
    targets: [
        .target(
            name: "FeatureMirror",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMirrorTests",
            dependencies: ["FeatureMirror"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
