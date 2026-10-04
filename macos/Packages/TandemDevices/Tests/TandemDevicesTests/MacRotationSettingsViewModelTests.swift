import Foundation
import Testing
import TandemStore
@testable import TandemDevices

/// E70-11: the Mac Settings "Rotate key" action's view model, against a fake ``MacKeyRotator``.
@Suite("MacRotationSettingsViewModel")
@MainActor
struct MacRotationSettingsViewModelTests {
    private final class FakeRotator: MacKeyRotator, @unchecked Sendable {
        var result: MacKeyRotationResult = .success(newFingerprint: "NEW")
        var pending: PendingRotation?
        var onRotate: (@MainActor @Sendable () -> Void)?
        private(set) var rotateCalls = 0
        private(set) var finishCalls = 0
        private(set) var cancelCalls = 0

        func rotate() async -> MacKeyRotationResult {
            rotateCalls += 1
            await onRotate?()
            return result
        }

        func pendingRotation() -> PendingRotation? { pending }

        func finishRotation() async throws { finishCalls += 1 }

        func cancelRotation() async throws { cancelCalls += 1 }
    }

    private final class Recorder: @unchecked Sendable {
        var states: [MacRotationState] = []
        var enabled: [Bool] = []
    }

    private nonisolated static let now = Date(timeIntervalSince1970: 1_000_000_000)

    private static func makeViewModel(
        rotator: FakeRotator,
        authenticated: Bool = true
    ) -> MacRotationSettingsViewModel {
        MacRotationSettingsViewModel(
            rotator: rotator,
            currentFingerprint: "OLD",
            hasAuthenticatedSession: authenticated,
            dateProvider: { now }
        )
    }

    @Test("macRotationSettingsViewModel_noAuthenticatedSession_actionDisabled")
    func noAuthenticatedSession_actionDisabled() {
        let viewModel = Self.makeViewModel(rotator: FakeRotator(), authenticated: false)

        viewModel.requestRotation()

        #expect(!viewModel.actionEnabled)
        #expect(viewModel.disabledReason == "Connect your phone to rotate the key")
        #expect(viewModel.state == .idle)
    }

    @Test("macRotationSettingsViewModel_userConfirms_reachesSuccessWithNewFingerprint")
    func userConfirms_reachesSuccessWithNewFingerprint() async {
        let rotator = FakeRotator()
        let viewModel = Self.makeViewModel(rotator: rotator)

        viewModel.requestRotation()
        #expect(viewModel.state == .confirming)
        await viewModel.confirm()

        #expect(viewModel.state == .success(newFingerprint: "NEW"))
        #expect(viewModel.currentFingerprint == "NEW")
        #expect(rotator.rotateCalls == 1)
    }

    @Test("macRotationSettingsViewModel_confirm_passesThroughInProgress")
    func confirm_passesThroughInProgress() async {
        let rotator = FakeRotator()
        let viewModel = Self.makeViewModel(rotator: rotator)
        viewModel.requestRotation()

        var observed: [MacRotationState] = []
        var enabledDuring: [Bool] = []
        let recorder = Recorder()
        rotator.onRotate = { recorder.states.append(viewModel.state); recorder.enabled.append(viewModel.actionEnabled) }
        await viewModel.confirm()

        observed = recorder.states
        enabledDuring = recorder.enabled
        #expect(observed == [.inProgress])
        #expect(enabledDuring == [false])
    }

    @Test("macRotationSettingsViewModel_initiatorRejected_showsFailedAndOldFingerprint")
    func initiatorRejected_showsFailedAndOldFingerprint() async {
        let rotator = FakeRotator()
        rotator.result = .failure(reason: "Phone rejected the new key")
        let viewModel = Self.makeViewModel(rotator: rotator)

        viewModel.requestRotation()
        await viewModel.confirm()

        #expect(viewModel.state == .failed(reason: "Phone rejected the new key"))
        #expect(viewModel.currentFingerprint == "OLD")
    }

    @Test("macRotationSettingsViewModel_userCancels_initiatorNeverCalled")
    func userCancels_initiatorNeverCalled() async {
        let rotator = FakeRotator()
        let viewModel = Self.makeViewModel(rotator: rotator)

        viewModel.requestRotation()
        viewModel.cancel()
        await viewModel.confirm()

        #expect(viewModel.state == .idle)
        #expect(rotator.rotateCalls == 0)
    }

    @Test("macRotationSettingsViewModel_dismissResult_returnsToIdle")
    func dismissResult_returnsToIdle() async {
        let rotator = FakeRotator()
        rotator.result = .failure(reason: "x")
        let viewModel = Self.makeViewModel(rotator: rotator)
        viewModel.requestRotation()
        await viewModel.confirm()

        viewModel.dismissResult()

        #expect(viewModel.state == .idle)
    }

    @Test("macRotationSettingsViewModel_phonesPending_showsWaitingTextWithNamesAndNoFinish")
    func phonesPending_showsWaitingText() {
        let rotator = FakeRotator()
        rotator.pending = PendingRotation(
            startedAt: Self.now.addingTimeInterval(-3600),
            phoneNames: ["Pixel 8", "Pixel 9"]
        )
        let viewModel = Self.makeViewModel(rotator: rotator)

        viewModel.refreshPending()

        #expect(viewModel.pendingText == "Waiting for 2 phones to confirm the new key")
        #expect(viewModel.pendingPhoneNames == ["Pixel 8", "Pixel 9"])
        #expect(!viewModel.canFinishPending)
    }

    @Test("macRotationSettingsViewModel_onePhonePending_usesSingular")
    func onePhonePending_usesSingular() {
        let rotator = FakeRotator()
        rotator.pending = PendingRotation(startedAt: Self.now, phoneNames: ["Pixel 8"])
        let viewModel = Self.makeViewModel(rotator: rotator)

        viewModel.refreshPending()

        #expect(viewModel.pendingText == "Waiting for 1 phone to confirm the new key")
    }

    @Test("macRotationSettingsViewModel_phonesPendingOver7Days_offersFinishAndCancel")
    func phonesPendingOver7Days_offersFinishAndCancel() async {
        let rotator = FakeRotator()
        rotator.pending = PendingRotation(
            startedAt: Self.now.addingTimeInterval(-TrustStore.gracePinLifetime),
            phoneNames: ["Pixel 8"]
        )
        let viewModel = Self.makeViewModel(rotator: rotator)
        viewModel.refreshPending()

        #expect(viewModel.canFinishPending)
        #expect(viewModel.finishWarning == "Pending phones will need to pair again")

        await viewModel.finishPending()
        #expect(rotator.finishCalls == 1)

        await viewModel.cancelPending()
        #expect(rotator.cancelCalls == 1)
    }

    @Test("macRotationSettingsViewModel_noPending_showsNothing")
    func noPending_showsNothing() {
        let viewModel = Self.makeViewModel(rotator: FakeRotator())

        viewModel.refreshPending()

        #expect(viewModel.pendingText == nil)
        #expect(!viewModel.canFinishPending)
    }
}
