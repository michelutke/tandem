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
        .package(path: "../TandemTestSupport"),
        .package(path: "../TandemProtocol"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "TandemStore",
            dependencies: [
                "TandemCrypto",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemStoreTests",
            dependencies: ["TandemStore", "TandemTestSupport", "TandemProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
