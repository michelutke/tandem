import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

@Suite("GracePinMaintenance admission")
struct GracePinAdmissionTests {
    private static let now = Date(timeIntervalSince1970: 2_000_000)

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private struct Rotated {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let oldPin: SpkiFingerprint
        let newPin: SpkiFingerprint
        let maintenance: GracePinMaintenance

        init() throws {
            oldPin = try GracePinAdmissionTests.fingerprint(0x01)
            newPin = try GracePinAdmissionTests.fingerprint(0x02)
            let record = PeerRecord(
                fingerprint: oldPin, displayName: "Phone", pairedAt: GracePinAdmissionTests.now,
                lastSeen: GracePinAdmissionTests.now, capabilities: []
            )
            try store.put(record)
            try store.rotatePrimary(of: record, to: newPin, now: GracePinAdmissionTests.now)
            maintenance = GracePinMaintenance(trustStore: store, dateProvider: { GracePinAdmissionTests.now })
        }
    }

    @Test
    func admit_primaryPin_returnsFalseAndKeepsGracePin() throws {
        let rotated = try Rotated()

        #expect(rotated.maintenance.admit(rotated.newPin) == false)
        #expect(try rotated.store.get(rotated.newPin)?.gracePin != nil)
    }

    @Test
    func admit_graceAfterRotatingSessionClosed_returnsTrue() throws {
        let rotated = try Rotated()
        let rotatingSession = TrustedPeer(fingerprint: rotated.oldPin, spkiDer: nil)

        #expect(!rotatingSession.authenticatedByGrace)
        #expect(rotated.maintenance.admit(rotated.oldPin) == true)
    }

    @Test
    func admit_secondGraceSession_isRefused() throws {
        let rotated = try Rotated()

        #expect(rotated.maintenance.admit(rotated.oldPin) == true)
        #expect(rotated.maintenance.admit(rotated.oldPin) == nil)
    }

    @Test
    func contains_usedGracePin_isFalse() throws {
        let rotated = try Rotated()
        let reader = TandemTrustStoreReader(trustStore: rotated.store, dateProvider: { Self.now })
        #expect(try reader.contains(rotated.oldPin))

        _ = rotated.maintenance.admit(rotated.oldPin)

        #expect(try !reader.contains(rotated.oldPin))
    }

    @Test
    func sessionClosed_graceAuthenticated_purgesGracePin() throws {
        let rotated = try Rotated()
        _ = rotated.maintenance.admit(rotated.oldPin)

        rotated.maintenance.sessionClosed(authenticatedBy: rotated.oldPin)

        #expect(try rotated.store.get(rotated.newPin)?.gracePin == nil)
    }
}
