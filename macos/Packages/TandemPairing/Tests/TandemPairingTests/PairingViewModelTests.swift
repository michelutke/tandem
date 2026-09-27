import CoreImage
import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemPairing

/// The Mac's pairing QR screen (E14-11, `docs/protocol/SPEC.md` § Pairing window). Time is driven
/// purely by a `ManualTestClock` bridged into a `DateProvider`, the same way ``PairingWindowTests``
/// drives ``PairingWindow`` itself -- ``PairingViewModel`` settles lazily on every read and never
/// mutates anything on its own except via ``PairingViewModel/tick()``/``PairingViewModel/regenerate()``.
@Suite("PairingViewModel")
struct PairingViewModelTests {

    @Test
    func pairingViewModel_renderedQrImage_decodesToCurrentPayload() throws {
        let viewModel = try Self.makeViewModel()
        let image = try #require(viewModel.qrImage)

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = try #require(detector?.features(in: image) as? [CIQRCodeFeature])
        let decoded = try #require(features.first?.messageString)

        #expect(decoded == viewModel.currentPayload.uri)
    }

    @Test
    func pairingViewModel_advance30s_countdownReads90s() throws {
        let clock = ManualTestClock()
        let viewModel = try Self.makeViewModel(clock: clock)

        clock.advance(by: .seconds(30))

        #expect(viewModel.remainingSeconds == 90)
    }

    @Test
    func pairingViewModel_advance120s_countdownZeroSameTickWindowCloses() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock)
        let viewModel = try Self.makeViewModel(clock: clock, window: window)

        clock.advance(by: .seconds(120))

        #expect(viewModel.remainingSeconds == 0)
        #expect(window.closedReason == .expired)
    }

    @Test
    func pairingViewModel_afterExpiry_regeneratedQrHasDifferentSecret() throws {
        let clock = ManualTestClock()
        let viewModel = try Self.makeViewModel(clock: clock)
        let originalSecret = viewModel.currentPayload.secret

        clock.advance(by: .seconds(120))
        viewModel.tick()

        #expect(viewModel.currentPayload.secret != originalSecret)
        #expect(viewModel.remainingSeconds == 120)
    }

    @Test
    func pairingViewModel_attemptsExhausted_showsAttemptsUsedUpWithRegenerate() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock, verifierResult: false)
        let viewModel = try Self.makeViewModel(clock: clock, window: window)

        for _ in 0..<3 {
            let token = try #require(window.admitCandidateToken())
            _ = window.candidateHellosCompleted(token)
            _ = window.submitPairRequest(token, proof: Data([9]))
        }

        #expect(viewModel.attemptsExhausted)
        #expect(
            PairingViewModel.attemptsExhaustedMessage
                == "Pairing attempts used up. Someone else may be trying to pair. Generate a new code."
        )

        let exhaustedSecret = viewModel.currentPayload.secret
        viewModel.regenerate()

        #expect(!viewModel.attemptsExhausted)
        #expect(viewModel.attemptsRemaining == 3)
        #expect(viewModel.currentPayload.secret != exhaustedSecret)
    }

    // MARK: - Fixtures

    private static func fixedFingerprint() throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: 0xAB, count: SpkiFingerprint.byteCount))
    }

    private static func makeWindow(
        clock: ManualTestClock,
        verifierResult: Bool = true
    ) -> PairingWindow {
        PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: verifierResult)
        )
    }

    private static func makeViewModel(
        clock: ManualTestClock = ManualTestClock(),
        window: PairingWindow? = nil
    ) throws -> PairingViewModel {
        PairingViewModel(
            window: window ?? Self.makeWindow(clock: clock),
            fingerprint: try Self.fixedFingerprint(),
            secretSource: SystemSecretSource(),
            addressSource: FakeLocalAddressSource(addresses: ["192.168.1.10"]),
            port: 54321,
            name: "Mac",
            dateProvider: FixedDateProvider(clock: clock).provider
        )
    }
}
