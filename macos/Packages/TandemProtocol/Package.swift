// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemProtocol",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemProtocol", targets: ["TandemProtocol"])
    ],
    dependencies: [
        // Must match the buf.build/apple/swift plugin version in protocol/buf.gen.yaml.
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
        // Used by ControlSessionRegistry for SpkiFingerprint key type
        .package(path: "../TandemCrypto"),
        // Test-only: FrameEncoder tests send into InMemoryConnectionPair (E00-25) and read the
        // per-direction capture, since TandemProtocol itself may not depend on TandemTransport
        // (PRD module rules: transport depends on protocol, never the reverse).
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "TandemProtocol",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "TandemCrypto"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemProtocolTests",
            dependencies: ["TandemProtocol", "TandemCrypto", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
