// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TandemDesign",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemDesign", targets: ["TandemDesign"])
    ],
    targets: [
        .target(
            name: "TandemDesign",
            resources: [.process("Fonts")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemDesignTests",
            dependencies: ["TandemDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
