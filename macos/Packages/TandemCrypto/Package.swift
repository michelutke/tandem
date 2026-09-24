// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemCrypto",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemCrypto", targets: ["TandemCrypto"])
    ],
    targets: [
        .target(
            name: "TandemCrypto",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemCryptoTests",
            dependencies: ["TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
