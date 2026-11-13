import AppKit
import FeatureCalls
import Foundation
import TandemDesign

/// In-app Answer / Decline alert for an incoming call, used when the system cannot deliver the
/// call notification (notifications denied), so a ringing call is never silent. One alert at a
/// time; ``remove(callId:)`` withdraws it when the call ends or is answered elsewhere.
@MainActor
final class AlertCallPresenter: CallAlertPresenter {
    nonisolated let responses: AsyncStream<CallAlertResponse>

    private let continuation: AsyncStream<CallAlertResponse>.Continuation
    private var showingId: String?

    init() {
        (responses, continuation) = AsyncStream<CallAlertResponse>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(callId: String, title: String, body: String) async -> Bool {
        guard showingId == nil else { return false }
        showingId = callId
        Task { @MainActor in show(callId: callId, title: title, body: body) }
        return true
    }

    func remove(callId: String) async {
        if showingId == callId { GlassDialog.abort() }
    }

    func finish() {
        if showingId != nil { GlassDialog.abort() }
        continuation.finish()
    }

    private func show(callId: String, title: String, body: String) {
        NSApp.activate()
        let choice = GlassDialog.runModal(
            title: title,
            message: body,
            actions: [
                GlassDialogAction("Answer", kind: .primary),
                GlassDialogAction("Decline", isSafeDefault: true)
            ]
        )
        showingId = nil
        switch choice {
        case 0: continuation.yield(CallAlertResponse(callId: callId, action: .answer))
        case 1: continuation.yield(CallAlertResponse(callId: callId, action: .decline))
        default: break
        }
    }
}
