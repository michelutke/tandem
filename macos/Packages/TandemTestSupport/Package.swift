// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemTestSupport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemTestSupport", targets: ["TandemTestSupport"])
    ],
    dependencies: [
        .package(path: "../TandemTransport")
    ],
    targets: [
        .target(
            name: "TandemTestSupport",
            dependencies: ["TandemTransport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTestSupportTests",
            dependencies: ["TandemTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
