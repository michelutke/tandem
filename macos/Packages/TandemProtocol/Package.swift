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
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1")
    ],
    targets: [
        .target(
            name: "TandemProtocol",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemProtocolTests",
            dependencies: ["TandemProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
