// swift-tools-version: 6.1
import PackageDescription

// Fixture for dependencyDenylist_swifterPackageAdded_exitsNonZero: no HTTP server library
// (invariant 2: no plaintext listener, no HTTP server, no WebDAV).
let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "FeatureFiles",
            dependencies: [
                .product(name: "Swifter", package: "swifter")
            ]
        )
    ]
)
