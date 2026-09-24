// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemTransport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemTransport", targets: ["TandemTransport"])
    ],
    targets: [
        .target(
            name: "TandemTransport",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTransportTests",
            dependencies: ["TandemTransport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
