// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemTransport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemTransport", targets: ["TandemTransport"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto")
    ],
    targets: [
        .target(
            name: "TandemTransport",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTransportTests",
            dependencies: [
                "TandemTransport",
                .product(name: "TandemCrypto", package: "TandemCrypto")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
