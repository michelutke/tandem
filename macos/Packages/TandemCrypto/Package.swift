// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemCrypto",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemCrypto", targets: ["TandemCrypto"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0")
    ],
    targets: [
        .target(
            name: "TandemCrypto",
            dependencies: [
                .product(name: "X509", package: "swift-certificates")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemCryptoTests",
            dependencies: ["TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
