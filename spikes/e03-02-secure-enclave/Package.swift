// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "se-identity-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "se-identity-spike",
            path: "Sources/se-identity-spike"
        )
    ]
)
