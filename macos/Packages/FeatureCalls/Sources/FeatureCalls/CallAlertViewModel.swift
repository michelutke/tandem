import Foundation
import Observation
import TandemCrypto
import TandemProtocol
import TandemStore

/// Incoming-call alert logic (E52-06, PRD F-8.4, UC-20). A `RINGING` incoming `CallEvent` presents
/// an alert titled with the cached contact's name, or the formatted number when none matches
/// (E51-04). Answer/Decline send `CallAction` on the CALLS channel; an `ACTIVE` call shows the
/// menu-bar Hang Up item (``showsHangUp``), and `ENDED` removes both. Caller names and numbers are
/// untrusted peer input: they pass ``DisplayStringSanitizer`` before presentation and are never
/// logged (invariant 7).
@MainActor
@Observable
public final class CallAlertViewModel {
    public static let alertBody = "Incoming call"

    /// Whether the menu bar offers Hang Up -- true while a call is `ACTIVE`.
    public var showsHangUp: Bool { activeCallId != nil }

    private(set) var activeCallId: String?

    private let presenter: any CallAlertPresenter
    private let session: any TandemSession
    private let contacts: any ContactsStore
    private let peer: SpkiFingerprint
    private let makeRequestId: @Sendable () -> String
    private let numberFormatter: PhoneNumberNormalizer

    @ObservationIgnored
    private nonisolated(unsafe) var eventTask: Task<Void, Never>?
    @ObservationIgnored
    private nonisolated(unsafe) var responseTask: Task<Void, Never>?

    public init(
        presenter: any CallAlertPresenter,
        session: any TandemSession,
        contacts: any ContactsStore,
        peer: SpkiFingerprint,
        makeRequestId: @escaping @Sendable () -> String = { UUID().uuidString },
        numberFormatter: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) {
        self.presenter = presenter
        self.session = session
        self.contacts = contacts
        self.peer = peer
        self.makeRequestId = makeRequestId
        self.numberFormatter = numberFormatter
    }

    deinit {
        eventTask?.cancel()
        responseTask?.cancel()
    }

    /// Starts observing the CALLS channel and the presenter's Answer/Decline responses.
    public func start() {
        eventTask?.cancel()
        responseTask?.cancel()
        let session = session
        let presenter = presenter
        eventTask = Task { [weak self] in
            for await frame in await session.receive(.calls) {
                guard case .callEvent(let event)? = frame.payload else { continue }
                await self?.handle(event)
            }
        }
        responseTask = Task { [weak self] in
            for await response in presenter.responses {
                switch response.action {
                case .answer: await self?.answer(callId: response.callId)
                case .decline: await self?.decline(callId: response.callId)
                }
            }
        }
    }

    public func handle(_ event: Tandem_V1_CallEvent) async {
        guard event.direction == .incoming else { return }
        switch event.state {
        case .ringing:
            await presenter.present(callId: event.callID, title: await title(for: event), body: Self.alertBody)
        case .active:
            await presenter.remove(callId: event.callID)
            activeCallId = event.callID
        case .ended:
            await presenter.remove(callId: event.callID)
            if activeCallId == event.callID { activeCallId = nil }
        default:
            break
        }
    }

    public func answer(callId: String) async {
        await send(.answer, callId: callId)
    }

    public func decline(callId: String) async {
        await send(.decline, callId: callId)
    }

    public func hangUp() async {
        guard let activeCallId else { return }
        await send(.hangup, callId: activeCallId)
    }

    private func send(_ type: Tandem_V1_CallActionType, callId: String) async {
        var action = Tandem_V1_CallAction()
        action.requestID = makeRequestId()
        action.callID = callId
        action.action = type
        try? await session.send(.calls, payload: .callAction(action))
    }

    private func title(for event: Tandem_V1_CallEvent) async -> String {
        if let name = await contactName(for: event) {
            return DisplayStringSanitizer.sanitize(Data(name.utf8), kind: .name)
        }
        let formatted = numberFormatter.internationalFormat(of: event.address) ?? event.address
        return DisplayStringSanitizer.sanitize(Data(formatted.utf8), kind: .name)
    }

    private func contactName(for event: Tandem_V1_CallEvent) async -> String? {
        if let contact = try? await contacts.lookup(peer: peer, number: event.address) {
            return contact.displayName
        }
        guard !event.normalizedE164.isEmpty,
              let contact = try? await contacts.lookup(peer: peer, number: event.normalizedE164) else { return nil }
        return contact.displayName
    }
}
