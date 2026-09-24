// swift-tools-version: 6.1
import PackageDescription

// Fixture: TandemTestSupport used correctly, only as a test-target dependency.
let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(name: "FeatureFiles"),
        .testTarget(
            name: "FeatureFilesTests",
            dependencies: [
                "FeatureFiles",
                .product(name: "TandemTestSupport", package: "TandemTestSupport")
            ]
        )
    ]
)
