// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "nwlistener-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "nwlistener-spike",
            path: "Sources/nwlistener-spike"
        )
    ]
)
