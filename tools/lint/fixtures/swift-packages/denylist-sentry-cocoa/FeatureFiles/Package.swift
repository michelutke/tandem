// swift-tools-version: 6.1
import PackageDescription

// Fixture for dependencyDenylist_sentryCocoaPackageAdded_exitsNonZero: no third-party
// crash-reporting or analytics SDK (cycle-4 decision).
let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa")
            ]
        )
    ]
)
