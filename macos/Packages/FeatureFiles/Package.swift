// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeatureFiles",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeatureFiles", targets: ["FeatureFiles"])
    ],
    dependencies: [
        .package(path: "../TandemProtocol"),
<<<<<<< Updated upstream
        .package(path: "../TandemTestSupport")
=======
        .package(path: "../TandemDesign")
>>>>>>> Stashed changes
    ],
    targets: [
        .target(
            name: "FeatureFiles",
<<<<<<< Updated upstream
            dependencies: ["TandemProtocol"],
=======
            dependencies: ["TandemProtocol", "TandemDesign"],
>>>>>>> Stashed changes
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFilesTests",
<<<<<<< Updated upstream
            dependencies: ["FeatureFiles", "TandemProtocol", "TandemTestSupport"],
=======
            dependencies: ["FeatureFiles", "TandemProtocol"],
>>>>>>> Stashed changes
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
