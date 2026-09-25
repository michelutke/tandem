// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemTransport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemTransport", targets: ["TandemTransport"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemStore"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "TandemTransport",
            dependencies: [
                .product(name: "TandemCrypto", package: "TandemCrypto"),
                .product(name: "TandemStore", package: "TandemStore")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTransportTests",
            dependencies: [
                "TandemTransport",
                .product(name: "TandemCrypto", package: "TandemCrypto"),
                .product(name: "TandemStore", package: "TandemStore"),
                .product(name: "TandemTestSupport", package: "TandemTestSupport")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
