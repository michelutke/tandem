// swift-tools-version: 6.1
import PackageDescription

// Security.framework is Apple-only; these files use SecItem*/SecKey*/SecKeychain*/OSStatus
// throughout and cannot be made portable, so they're excluded from the Linux build (the
// fuzz-libfuzzer.yml CI container) -- only SpkiFingerprint/ConfirmationCode/PairingProof and
// their non-Sec* dependents need to build there, for FrameEnvelopeFuzzerCore's transitive use of
// TandemProtocol -> TandemCrypto (ControlSessionRegistry's SpkiFingerprint key type).
#if canImport(Darwin)
let macOSOnlySecuritySources: [String] = []
#else
let macOSOnlySecuritySources = [
    "FileKeychain.swift",
    "IdentityCertProvider.swift",
    "IdentityKeyProvider.swift",
    "KeychainStore.swift",
    "RotationKeyProvider.swift",
    "SecIdentityProvider.swift",
    "SecItemKeychainStore.swift"
]
#endif

let package = Package(
    name: "TandemCrypto",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TandemCrypto", targets: ["TandemCrypto"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.0"),
        // Linux-only: CryptoKit is Apple-only, so SHA256/HMAC<SHA256> usage falls back to
        // swift-crypto's API-compatible `Crypto` module there. Pinned to 4.5.2, not the newer
        // 5.0.0 that swift-certificates' own "3.12.3"..<"6.0.0" range would otherwise resolve to
        // unconstrained -- 5.0.0's manifest declares swift-tools-version 6.2, which the
        // fuzz-libfuzzer.yml CI container (swift:6.1 Docker image) cannot even parse, so
        // resolution fails there with "incompatible tools version" (reproduced locally via
        // `docker run swift:6.1 swift package resolve`). 4.5.2 declares swift-tools-version 6.1.
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .target(
            name: "TandemCrypto",
            dependencies: [
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ],
            exclude: macOSOnlySecuritySources,
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TandemCryptoTests",
            dependencies: ["TandemCrypto"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
