import FeatureCalls
import Foundation
import TandemCrypto
import TandemStore
import Testing
@testable import TandemProtocol

@MainActor
@Suite struct CallAlertViewModelTests {
    nonisolated private static let peer: SpkiFingerprint = {
        // swiftlint:disable:next force_try
        try! SpkiFingerprint(bytes: Data(repeating: 0x07, count: SpkiFingerprint.byteCount))
    }()

    @MainActor private struct Harness {
        let presenter = RecordingCallAlertPresenter()
        let session = FakeTandemSession()
        let contacts = InMemoryContactsStore(normalizer: PhoneNumberNormalizer(defaultRegion: "CH"))
        let viewModel: CallAlertViewModel

        init() {
            viewModel = CallAlertViewModel(
                presenter: presenter,
                session: session,
                contacts: contacts,
                peer: CallAlertViewModelTests.peer,
                makeRequestId: { "req-1" },
                numberFormatter: PhoneNumberNormalizer(defaultRegion: "CH")
            )
        }

        func seedContact(name: String, number: String) async {
            await contacts.apply(
                peer: CallAlertViewModelTests.peer,
                contacts: [
                    ContactRecord(
                        contactId: "c1",
                        displayName: name,
                        phoneNumbers: [ContactPhoneRecord(number: number)],
                        updatedAtMs: 1
                    )
                ],
                deletedContactIds: [],
                watermarkMs: nil
            )
        }

        func sentActions() async -> [Tandem_V1_CallAction] {
            await session.sent.compactMap { frame in
                guard frame.channel == .calls, case .callAction(let action) = frame.payload else { return nil }
                return action
            }
        }
    }

    private static func event(
        _ state: Tandem_V1_CallState,
        callId: String = "call-1",
        address: String = "+41791234567"
    ) -> Tandem_V1_CallEvent {
        var event = Tandem_V1_CallEvent()
        event.callID = callId
        event.direction = .incoming
        event.state = state
        event.address = address
        event.normalizedE164 = address
        return event
    }

    @Test func callAlertViewModel_ringingCachedNumber_presentsContactName() async {
        let harness = Harness()
        await harness.seedContact(name: "Ada Lovelace", number: "079 123 45 67")

        await harness.viewModel.handle(Self.event(.ringing))

        let presented = await harness.presenter.presented
        #expect(presented.map(\.title) == ["Ada Lovelace"])
        #expect(presented.map(\.callId) == ["call-1"])
    }

    @Test func callAlertViewModel_ringingUnresolvedNumber_presentsFormattedNumber() async {
        let harness = Harness()

        await harness.viewModel.handle(Self.event(.ringing))

        let presented = await harness.presenter.presented
        #expect(presented.map(\.title) == ["+41 79 123 45 67"])
    }

    @Test func callAlertViewModel_answerTapped_sendsAnswerAction() async {
        let harness = Harness()

        await harness.viewModel.answer(callId: "call-1")

        let actions = await harness.sentActions()
        #expect(actions.count == 1)
        #expect(actions.first?.action == .answer)
        #expect(actions.first?.callID == "call-1")
        #expect(actions.first?.requestID == "req-1")
    }

    @Test func callAlertViewModel_declineTapped_sendsDeclineAction() async {
        let harness = Harness()

        await harness.viewModel.decline(callId: "call-1")

        let actions = await harness.sentActions()
        #expect(actions.count == 1)
        #expect(actions.first?.action == .decline)
        #expect(actions.first?.callID == "call-1")
    }

    @Test func callAlertViewModel_activeEvent_showsHangUpThatSendsHangup() async {
        let harness = Harness()

        await harness.viewModel.handle(Self.event(.active))
        #expect(harness.viewModel.showsHangUp)

        await harness.viewModel.hangUp()

        let actions = await harness.sentActions()
        #expect(actions.count == 1)
        #expect(actions.first?.action == .hangup)
        #expect(actions.first?.callID == "call-1")
    }

    @Test func callAlertViewModel_endedEvent_removesAlertAndHangUp() async {
        let harness = Harness()
        await harness.viewModel.handle(Self.event(.ringing))
        await harness.viewModel.handle(Self.event(.active))

        await harness.viewModel.handle(Self.event(.ended))

        #expect(!harness.viewModel.showsHangUp)
        let removed = await harness.presenter.removedCallIds
        #expect(removed.contains("call-1"))
    }

    @Test func callAlertViewModel_contactNameWithBidiOverride_presentedSanitized() async {
        let harness = Harness()
        await harness.seedContact(name: "Ev\u{202E}il", number: "+41791234567")

        await harness.viewModel.handle(Self.event(.ringing))

        let presented = await harness.presenter.presented
        #expect(presented.map(\.title) == ["Evil"])
    }

    @Test func callAlertViewModel_presenterResponse_sendsMatchingAction() async {
        let harness = Harness()
        harness.viewModel.start()

        await harness.presenter.inject(CallAlertResponse(callId: "call-9", action: .decline))
        for _ in 0..<200 where await harness.sentActions().isEmpty {
            await Task.yield()
        }

        let actions = await harness.sentActions()
        #expect(actions.first?.action == .decline)
        #expect(actions.first?.callID == "call-9")
    }
}
