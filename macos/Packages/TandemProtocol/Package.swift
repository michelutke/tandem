// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemProtocol",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemProtocol", targets: ["TandemProtocol"])
    ],
    targets: [
        .target(
            name: "TandemProtocol",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemProtocolTests",
            dependencies: ["TandemProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
