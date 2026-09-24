// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemStore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemStore", targets: ["TandemStore"])
    ],
    targets: [
        .target(
            name: "TandemStore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemStoreTests",
            dependencies: ["TandemStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
