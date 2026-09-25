// swift-tools-version: 6.1
import PackageDescription

// E00-29: fixture for tools/lint/test/swiftpm_resolved_only_test.sh. The manifest requires
// swift-protobuf 1.38.0 but the checked-in Package.resolved (below) pins 1.38.1, so resolving
// with --only-use-versions-from-resolved-file must fail.
let package = Package(
    name: "MismatchedPackage",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.0")
    ],
    targets: [
        .target(
            name: "MismatchedPackage",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        )
    ]
)
