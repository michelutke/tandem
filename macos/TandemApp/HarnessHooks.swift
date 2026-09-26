#if DEBUG
import Foundation
import Network
import Security
import TandemCrypto
import TandemStore
import TandemTransport

/// Debug-only E15-22 CI harness launch hooks (D-75). Every hook here is compiled only under
/// `#if DEBUG` and gated by its own launch argument, so a Release build never links or runs any of
/// it -- the E00-30 scan proves the `HarnessSeedTrust`, `HarnessClearTrust` and
/// `HarnessListenerPort` strings never reach a Release binary.
///
/// Trust seeding/clearing run in the *same* Tandem.app binary as the identity they touch: a
/// file-keychain item's ACL is bound to the creating application, so a separate `harness-seed`
/// executable reading or writing a trust record Tandem.app created would trigger a Keychain
/// confirmation prompt (D-75). Each one-shot hook performs its single action and exits -- it never
/// falls through to the ordinary menu bar UI.
enum HarnessHooks {

    /// Checks `-HarnessSeedTrust <path>` and `-HarnessClearTrust`; if either is present, performs
    /// the action and terminates the process. Returns normally (does nothing) if neither is set.
    static func runOneShotHooksIfRequested() {
        if let path = UserDefaults.standard.string(forKey: "HarnessSeedTrust") {
            seedTrust(fromFixtureAt: path)
            exit(0)
        }
        if UserDefaults.standard.bool(forKey: "HarnessClearTrust") {
            clearTrust()
            exit(0)
        }
    }

    /// Starts the mTLS listener on `-HarnessListenerPort <port>` against the harness keychain's
    /// identity and trust store (E15-22). Does nothing if the argument isn't set. The listener
    /// keeps running for the life of the process, admitting only connections whose presented SPKI
    /// fingerprint matches a trust record seeded by `-HarnessSeedTrust` -- there is no pairing
    /// window in the harness (the live pairing state machine, E14-02, is exercised by its own
    /// harness hook once E14-01/E14-02 land).
    static func startListenerIfRequested() {
        guard let portString = UserDefaults.standard.string(forKey: "HarnessListenerPort"),
              let rawPort = UInt16(portString),
              let port = NWEndpoint.Port(rawValue: rawPort) else { return }

        let keychainStore = KeychainStoreFactory.make()
        let identityBootstrapper = IdentityBootstrapper(keychainStore: keychainStore)
        identityBootstrapper.bootstrapIdentity()

        guard case .ready(let identity) = identityBootstrapper.identityState else {
            let state = identityBootstrapper.identityState
            fatalError("-HarnessListenerPort requested but identity is not ready: \(state)")
        }
        printIdentitySpkiFingerprint(identity: identity)

        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: TandemTrustStoreReader(trustStore: TrustStore(keychainStore: keychainStore)),
            window: NeverOpenPairingWindow()
        )
        let controller = ListenerController(
            identityStateProvider: identityBootstrapper,
            listenerFactory: NWListenerFactory(),
            port: port,
            verify: verify
        )
        do {
            retainedListener = try controller.start()
        } catch {
            fatalError("-HarnessListenerPort failed to start listener on port \(rawPort): \(error)")
        }
    }

    /// Keeps the started `NWListener` alive for the process lifetime -- nothing else retains it
    /// once `startListenerIfRequested()` returns.
    nonisolated(unsafe) private static var retainedListener: NWListener?

    private static func seedTrust(fromFixtureAt path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let fixture = try JSONDecoder().decode(HarnessPeerRecordFixture.self, from: data)
            let trustStore = TrustStore(keychainStore: KeychainStoreFactory.make())
            try trustStore.put(try fixture.makePeerRecord())
        } catch {
            fatalError("-HarnessSeedTrust failed reading \(path): \(error)")
        }
    }

    private static func clearTrust() {
        do {
            let trustStore = TrustStore(keychainStore: KeychainStoreFactory.make())
            for record in try trustStore.list() {
                try trustStore.delete(record.fingerprint)
            }
        } catch {
            fatalError("-HarnessClearTrust failed: \(error)")
        }
    }

    /// Prints the harness identity's SPKI fingerprint to stdout so the CI driver script can
    /// confirm, across a kill/relaunch of the same on-disk keychain, that the identity is
    /// unchanged -- without any second binary reading the keychain itself (the same cross-binary
    /// ACL-prompt concern `-HarnessSeedTrust`/`-HarnessClearTrust` avoid, D-75).
    private static func printIdentitySpkiFingerprint(identity: SecIdentity) {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            return
        }
        let certificateDER = SecCertificateCopyData(certificate) as Data
        guard let spkiDER = try? LeafSpkiExtractor.subjectPublicKeyInfoDER(certificateDER: certificateDER),
              let fingerprint = try? SpkiFingerprint.of(spkiDer: spkiDER) else {
            return
        }
        print("harness-identity-spki: \(fingerprint.hexString)")
        fflush(stdout)
    }
}

/// No pairing window in the harness: connections are admitted only via a seeded trust record,
/// never via the pairing-candidate relaxation (D-18).
private struct NeverOpenPairingWindow: PairingWindowState {
    var isOpen: Bool { false }
    func admitCandidate() -> Bool { false }
    func releaseCandidate() {}
}

/// JSON fixture for `-HarnessSeedTrust <path>`: hex/ISO 8601 fields instead of `PeerRecord`'s own
/// Foundation `Codable` encoding (raw bytes as base64, dates as `timeIntervalSinceReferenceDate`),
/// so the CI driver script can generate the fixture without reproducing Foundation's date/data
/// encoding.
private struct HarnessPeerRecordFixture: Decodable {
    let fingerprintHex: String
    let displayName: String
    let pairedAt: String
    let lastSeen: String
    let capabilities: [String]

    enum FixtureError: Error {
        case invalidFingerprintHex
        case invalidDate
    }

    func makePeerRecord() throws -> PeerRecord {
        guard let fingerprintBytes = Data(harnessHexString: fingerprintHex) else {
            throw FixtureError.invalidFingerprintHex
        }
        let formatter = ISO8601DateFormatter()
        guard let pairedAtDate = formatter.date(from: pairedAt),
              let lastSeenDate = formatter.date(from: lastSeen) else {
            throw FixtureError.invalidDate
        }
        return PeerRecord(
            fingerprint: try SpkiFingerprint(bytes: fingerprintBytes),
            displayName: displayName,
            pairedAt: pairedAtDate,
            lastSeen: lastSeenDate,
            capabilities: capabilities
        )
    }
}

private extension Data {
    init?(harnessHexString hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
#endif
