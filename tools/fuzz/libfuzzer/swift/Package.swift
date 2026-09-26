// swift-tools-version: 6.1
import PackageDescription

// E15-14: standalone package (outside macos/Packages, so macos/test-packages.sh and
// tools/lint/swift-package-rules.rb never touch it) holding the libFuzzer harness for
// TandemProtocol's FrameDecoder. `FrameEnvelopeFuzzerCore` is a plain library: it builds and
// tests with a stock `swift build`/`swift test` on any Swift 6.1+ toolchain (macOS or Linux),
// no sanitizer flags required. The actual libFuzzer binary is assembled by
// tools/fuzz/libfuzzer/smoke.sh, which compiles fuzzer-entry/LLVMFuzzerEntry.swift directly with
// `swiftc -sanitize=fuzzer,address` against this library — that file is deliberately outside
// Sources/ so SwiftPM never tries to build it as a target (see smoke.sh and README.md).
let package = Package(
    name: "FrameEnvelopeFuzzer",
    platforms: [.macOS(.v15)],
    products: [
        // `.static`, not the default "automatic": build_fuzz_target.sh links a real archive
        // straight off disk (raw `swiftc`, not `swift build`), which only an explicit library
        // type reliably produces at `swift build --show-bin-path`.
        .library(name: "FrameEnvelopeFuzzerCore", type: .static, targets: ["FrameEnvelopeFuzzerCore"])
    ],
    dependencies: [
        .package(path: "../../../../macos/Packages/TandemProtocol")
    ],
    targets: [
        .target(
            name: "FrameEnvelopeFuzzerCore",
            dependencies: [.product(name: "TandemProtocol", package: "TandemProtocol")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FrameEnvelopeFuzzerCoreTests",
            dependencies: ["FrameEnvelopeFuzzerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
