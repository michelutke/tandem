// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FixturePackage",
    dependencies: [
        .package(url: "https://github.com/example/unregistered-swift-package.git", exact: "1.0.0")
    ]
)
