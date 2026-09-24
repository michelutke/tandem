// swift-tools-version: 6.1
import PackageDescription

// Fixture for packageGraphCheck_featureDependsOnFeatureFixture_exitsNonZero: a Feature package
// must never depend on another Feature package.
let package = Package(
    name: "FeatureClipboard",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../FeatureFiles")
    ],
    targets: [
        .target(
            name: "FeatureClipboard",
            dependencies: [
                .product(name: "FeatureFiles", package: "FeatureFiles")
            ]
        )
    ]
)
