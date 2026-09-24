// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemPairing",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemPairing", targets: ["TandemPairing"])
    ],
    targets: [
        .target(
            name: "TandemPairing",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemPairingTests",
            dependencies: ["TandemPairing"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
