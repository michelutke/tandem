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
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemTestSupport"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0")
    ],
    targets: [
        .target(
            name: "TandemTransport",
            dependencies: [
                .product(name: "TandemCrypto", package: "TandemCrypto"),
                .product(name: "TandemStore", package: "TandemStore"),
                .product(name: "TandemProtocol", package: "TandemProtocol")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTransportTests",
            dependencies: [
                "TandemTransport",
                .product(name: "TandemCrypto", package: "TandemCrypto"),
                .product(name: "TandemStore", package: "TandemStore"),
                .product(name: "TandemTestSupport", package: "TandemTestSupport"),
                .product(name: "X509", package: "swift-certificates")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
