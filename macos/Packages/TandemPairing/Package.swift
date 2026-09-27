// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemPairing",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemPairing", targets: ["TandemPairing"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemTransport"),
        .package(path: "../TandemStore"),
        .package(path: "../TandemProtocol"),
        .package(path: "../TandemDesign"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "TandemPairing",
            dependencies: ["TandemCrypto", "TandemTransport", "TandemStore", "TandemProtocol", "TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemPairingTests",
            dependencies: [
                "TandemPairing",
                "TandemCrypto",
                "TandemTransport",
                "TandemStore",
                "TandemProtocol",
                "TandemTestSupport"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
