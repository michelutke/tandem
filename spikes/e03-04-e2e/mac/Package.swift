// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "e2e-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "e2e-mac",
            path: "Sources/e2e-mac"
        )
    ]
)
