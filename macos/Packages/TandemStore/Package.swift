// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemStore", targets: ["TandemStore"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "TandemStore",
            dependencies: ["TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemStoreTests",
            dependencies: ["TandemStore", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
