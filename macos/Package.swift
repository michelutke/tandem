// swift-tools-version: 6.1
import PackageDescription

// CI-only aggregate: compiles the shared dependency graph once and hosts every local package's
// test target. Each package keeps its own Package.swift/Tests; the target paths here keep
// the tests' `#filePath`-relative lookups (repo root, package Sources) unchanged. It lives at the
// macos/ root because SwiftPM rejects target paths outside the package root.
// Package.resolved here must stay in sync with the per-package Package.resolved files.
let x509 = Target.Dependency.product(name: "X509", package: "swift-certificates")

let package = Package(
    name: "PackageTests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "Packages/../Packages/FeatureCalls"),
        .package(path: "Packages/../Packages/FeatureClipboard"),
        .package(path: "Packages/../Packages/FeatureFiles"),
        .package(path: "Packages/../Packages/FeatureFocus"),
        .package(path: "Packages/../Packages/FeatureMedia"),
        .package(path: "Packages/../Packages/FeatureMessaging"),
        .package(path: "Packages/../Packages/FeatureMirror"),
        .package(path: "Packages/../Packages/FeatureNotifications"),
        .package(path: "Packages/../Packages/TandemCrypto"),
        .package(path: "Packages/../Packages/TandemDesign"),
        .package(path: "Packages/../Packages/TandemDevices"),
        .package(path: "Packages/../Packages/TandemPairing"),
        .package(path: "Packages/../Packages/TandemProtocol"),
        .package(path: "Packages/../Packages/TandemStore"),
        .package(path: "Packages/../Packages/TandemTestSupport"),
        .package(path: "Packages/../Packages/TandemTransport"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0")
    ],
    targets: [
        .testTarget(
            name: "FeatureCallsTests",
            dependencies: ["FeatureCalls", "TandemCrypto", "TandemProtocol", "TandemStore", "TandemTestSupport"],
            path: "Packages/FeatureCalls/Tests/FeatureCallsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFocusTests",
            dependencies: ["FeatureFocus", "TandemCrypto", "TandemProtocol", "TandemTransport", "TandemTestSupport"],
            path: "Packages/FeatureFocus/Tests/FeatureFocusTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMediaTests",
            dependencies: ["FeatureMedia", "TandemProtocol", "TandemTestSupport"],
            path: "Packages/FeatureMedia/Tests/FeatureMediaTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureClipboardTests",
            dependencies: ["FeatureClipboard", "TandemTestSupport", "TandemProtocol"],
            path: "Packages/FeatureClipboard/Tests/FeatureClipboardTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureFilesTests",
            dependencies: ["FeatureFiles", "TandemProtocol", "TandemCrypto", "TandemTestSupport"],
            path: "Packages/FeatureFiles/Tests/FeatureFilesTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMessagingTests",
            dependencies: ["FeatureMessaging", "TandemTestSupport", "TandemProtocol", "TandemCrypto", "TandemStore"],
            path: "Packages/FeatureMessaging/Tests/FeatureMessagingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureMirrorTests",
            dependencies: ["FeatureMirror", "TandemCrypto", "TandemProtocol", "TandemTransport", "TandemTestSupport"],
            path: "Packages/FeatureMirror/Tests/FeatureMirrorTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeatureNotificationsTests",
            dependencies: ["FeatureNotifications", "TandemTestSupport", "TandemProtocol", "TandemCrypto"],
            path: "Packages/FeatureNotifications/Tests/FeatureNotificationsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemCryptoTests",
            dependencies: ["TandemCrypto"],
            path: "Packages/TandemCrypto/Tests/TandemCryptoTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemDesignTests",
            dependencies: ["TandemDesign"],
            path: "Packages/TandemDesign/Tests/TandemDesignTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemDevicesTests",
            dependencies: ["TandemDevices", "TandemCrypto", "TandemStore", "TandemTestSupport"],
            path: "Packages/TandemDevices/Tests/TandemDevicesTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemPairingTests",
            dependencies: [
                "TandemPairing",
                "TandemCrypto",
                "TandemDesign",
                "TandemTransport",
                "TandemStore",
                "TandemProtocol",
                "TandemTestSupport"
            ],
            path: "Packages/TandemPairing/Tests/TandemPairingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemProtocolTests",
            dependencies: ["TandemProtocol", "TandemCrypto", "TandemTestSupport"],
            path: "Packages/TandemProtocol/Tests/TandemProtocolTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemStoreTests",
            dependencies: ["TandemStore", "TandemTestSupport", "TandemProtocol"],
            path: "Packages/TandemStore/Tests/TandemStoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTestSupportTests",
            dependencies: ["TandemTestSupport", x509],
            path: "Packages/TandemTestSupport/Tests/TandemTestSupportTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemTransportTests",
            dependencies: ["TandemTransport", "TandemCrypto", "TandemStore", "TandemTestSupport", x509],
            path: "Packages/TandemTransport/Tests/TandemTransportTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
