// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemDevices",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemDevices", targets: ["TandemDevices"])
    ],
    dependencies: [
        .package(path: "../TandemCrypto"),
        .package(path: "../TandemStore"),
        .package(path: "../TandemDesign"),
        .package(path: "../TandemTestSupport")
    ],
    targets: [
        .target(
            name: "TandemDevices",
            dependencies: ["TandemCrypto", "TandemStore", "TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemDevicesTests",
            dependencies: ["TandemDevices", "TandemCrypto", "TandemStore", "TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
