// swift-tools-version: 6.1
import PackageDescription

// Fixture: TandemTestSupport is a test-support module (ManualTestClock, InMemoryConnectionPair);
// it must only ever be a test-target dependency, never a regular target dependency.
let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            dependencies: [
                .product(name: "TandemTestSupport", package: "TandemTestSupport")
            ]
        )
    ]
)
