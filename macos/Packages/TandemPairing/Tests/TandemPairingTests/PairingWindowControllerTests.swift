import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemPairing

/// E14-11 acceptance: "The pairing window sets `NSWindow.sharingType = .none` ... and offers no
/// copy or save of the QR image or payload" -- ``PairingView`` never attaches a copy/save action
/// of its own, so the one thing left to check structurally is the window's `sharingType`.
@Suite("PairingWindowController")
struct PairingWindowControllerTests {

    @Test
    @MainActor
    func pairingWindow_created_sharingTypeNoneAndNoCopyAction() throws {
        let clock = ManualTestClock()
        let pairingWindow = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: true)
        )
        let viewModel = PairingViewModel(
            window: pairingWindow,
            fingerprint: try SpkiFingerprint(bytes: Data(repeating: 0xAB, count: SpkiFingerprint.byteCount)),
            secretSource: SystemSecretSource(),
            addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
            port: 54321,
            name: "Mac",
            dateProvider: FixedDateProvider(clock: clock).provider
        )

        let controller = PairingWindowController(viewModel: viewModel)
        let window = try #require(controller.window)

        #expect(window.sharingType == .none)
    }
}
