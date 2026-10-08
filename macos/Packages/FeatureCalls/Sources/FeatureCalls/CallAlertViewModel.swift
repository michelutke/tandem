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
/// The call the Calls section's in-call bar shows: sanitized caller title and, when a clock was
/// injected, when the call became active.
public struct ActiveCallInfo: Equatable, Sendable {
    public let callId: String
    public let title: String
    public let startedAt: Date?
    /// An outgoing call the phone has not reported connected yet; shown without a timer.
    public let isDialing: Bool

    public init(callId: String, title: String, startedAt: Date?, isDialing: Bool = false) {
        self.callId = callId
        self.title = title
        self.startedAt = startedAt
        self.isDialing = isDialing
    }

    /// "Calling Ada." style line while dialing (ui-spec call.dialingNamed), else the caller title.
    public var displayTitle: String {
        isDialing ? "Calling \(title)\u{2026}" : title
    }

    /// "04:12" (or "1:04:12" past an hour); "00:00" when no clock was injected.
    public func elapsedText(at date: Date) -> String {
        guard let startedAt else { return "00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        let (hours, minutes, rest) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}

@MainActor
@Observable
public final class CallAlertViewModel {
    public static let alertBody = "Incoming call"

    /// Whether the menu bar offers Hang Up -- true while a call is `ACTIVE`.
    public var showsHangUp: Bool { activeCallId != nil || activeCall != nil }

    private(set) var activeCallId: String?

    /// The `ACTIVE` call in either direction, for the in-call bar; cleared when it `ENDED`.
    public private(set) var activeCall: ActiveCallInfo?

    private let presenter: any CallAlertPresenter
    private let session: any TandemSession
    private let contacts: any ContactsStore
    private let peer: SpkiFingerprint
    private let makeRequestId: @Sendable () -> String
    private let numberFormatter: PhoneNumberNormalizer
    private let now: (@Sendable () -> Date)?

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
        numberFormatter: PhoneNumberNormalizer = PhoneNumberNormalizer(),
        now: (@Sendable () -> Date)? = nil
    ) {
        self.presenter = presenter
        self.session = session
        self.contacts = contacts
        self.peer = peer
        self.makeRequestId = makeRequestId
        self.numberFormatter = numberFormatter
        self.now = now
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
        let isIncoming = event.direction == .incoming
        switch event.state {
        case .ringing where isIncoming:
            await presenter.present(callId: event.callID, title: await title(for: event), body: Self.alertBody)
        case .active:
            if isIncoming {
                await presenter.remove(callId: event.callID)
                activeCallId = event.callID
            }
            activeCall = ActiveCallInfo(callId: event.callID, title: await title(for: event), startedAt: now?())
        case .dialing where !isIncoming:
            activeCall = ActiveCallInfo(
                callId: event.callID, title: await title(for: event), startedAt: nil, isDialing: true
            )
        case .ended:
            if isIncoming { await presenter.remove(callId: event.callID) }
            if activeCallId == event.callID { activeCallId = nil }
            if activeCall?.callId == event.callID { activeCall = nil }
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
        guard let callId = activeCallId ?? activeCall?.callId else { return }
        await send(.hangup, callId: callId)
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
