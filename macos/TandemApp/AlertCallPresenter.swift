import AppKit
import FeatureCalls
import Foundation
import TandemDesign

/// In-app Answer / Decline alert for an incoming call, used when the system cannot deliver the
/// call notification (notifications denied), so a ringing call is never silent. One alert at a
/// time, shown non-modally with no default button (Return does nothing, Escape only dismisses it);
/// ``remove(callId:)`` withdraws it when the call ends or is answered elsewhere.
@MainActor
final class AlertCallPresenter: CallAlertPresenter {
    nonisolated let responses: AsyncStream<CallAlertResponse>

    private let continuation: AsyncStream<CallAlertResponse>.Continuation
    private var showingId: String?
    private var dialog: GlassDialogHandle?

    init() {
        (responses, continuation) = AsyncStream<CallAlertResponse>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(callId: String, title: String, body: String) async -> Bool {
        guard showingId == nil else { return false }
        showingId = callId
        show(callId: callId, title: title, body: body)
        return true
    }

    func remove(callId: String) async {
        if showingId == callId { withdraw() }
    }

    func finish() {
        withdraw()
        continuation.finish()
    }

    private func withdraw() {
        dialog?.close()
        dialog = nil
        showingId = nil
    }

    private func show(callId: String, title: String, body: String) {
        NSApp.activate()
        dialog = GlassDialog.present(
            title: title,
            message: body,
            actions: [
                GlassDialogAction("Answer", kind: .primary),
                GlassDialogAction("Decline")
            ]
        ) { [weak self] choice in
            self?.dialog = nil
            self?.showingId = nil
            switch choice {
            case 0: self?.continuation.yield(CallAlertResponse(callId: callId, action: .answer))
            case 1: self?.continuation.yield(CallAlertResponse(callId: callId, action: .decline))
            default: break
            }
        }
    }
}
