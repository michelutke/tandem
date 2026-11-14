import AppKit
import FeatureFiles
import Foundation
import TandemDesign

/// In-app Accept / Decline prompt for an incoming file, shown as an alert so the offer is
/// answerable even when the system cannot deliver the notification (an unsigned debug build).
/// Offers are shown one at a time; ``remove(offerId:)`` withdraws a queued or visible one.
@MainActor
final class AlertAcceptPromptPresenter: AcceptPromptPresenter {
    private struct Offer {
        let id: String
        let name: String
        let size: UInt64
    }

    nonisolated let responses: AsyncStream<AcceptPromptResponse>

    private let continuation: AsyncStream<AcceptPromptResponse>.Continuation
    private var queue: [Offer] = []
    private var showingId: String?
    private var dialog: GlassDialogHandle?

    init() {
        (responses, continuation) = AsyncStream<AcceptPromptResponse>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(offerId: String, displayName: String, size: UInt64) async {
        queue.append(Offer(id: offerId, name: displayName, size: size))
        showNext()
    }

    func remove(offerId: String) async {
        queue.removeAll { $0.id == offerId }
        guard showingId == offerId else { return }
        withdraw()
        showNext()
    }

    func finish() {
        queue.removeAll()
        withdraw()
        continuation.finish()
    }

    private func withdraw() {
        dialog?.close()
        dialog = nil
        showingId = nil
    }

    private func showNext() {
        guard showingId == nil, !queue.isEmpty else { return }
        let offer = queue.removeFirst()
        showingId = offer.id
        show(offer)
    }

    private func show(_ offer: Offer) {
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(clamping: offer.size), countStyle: .file)
        NSApp.activate()
        dialog = GlassDialog.present(
            title: "Incoming file",
            message: "\(offer.name) (\(formattedSize))",
            actions: [
                GlassDialogAction("Accept", kind: .primary),
                GlassDialogAction("Decline", isSafeDefault: true)
            ]
        ) { [weak self] choice in
            self?.dialog = nil
            self?.showingId = nil
            switch choice {
            case 0: self?.continuation.yield(AcceptPromptResponse(offerId: offer.id, decision: .accept))
            case 1: self?.continuation.yield(AcceptPromptResponse(offerId: offer.id, decision: .decline))
            default: break
            }
            self?.showNext()
        }
    }
}

/// Presents an offer on both prompts and answers with whichever the user uses first; the other is
/// withdrawn by the flow's `remove` once the offer is decided.
final class CompositeAcceptPromptPresenter: AcceptPromptPresenter, @unchecked Sendable {
    let responses: AsyncStream<AcceptPromptResponse>

    private let presenters: [any AcceptPromptPresenter]
    private let forwarders: [Task<Void, Never>]

    init(_ presenters: [any AcceptPromptPresenter]) {
        self.presenters = presenters
        let (merged, continuation) = AsyncStream<AcceptPromptResponse>.makeStream(bufferingPolicy: .unbounded)
        responses = merged
        let forwarders = presenters.map { presenter in
            Task {
                for await response in presenter.responses { continuation.yield(response) }
            }
        }
        self.forwarders = forwarders
        Task {
            for forwarder in forwarders { await forwarder.value }
            continuation.finish()
        }
    }

    func present(offerId: String, displayName: String, size: UInt64) async {
        for presenter in presenters {
            await presenter.present(offerId: offerId, displayName: displayName, size: size)
        }
    }

    func remove(offerId: String) async {
        for presenter in presenters {
            await presenter.remove(offerId: offerId)
        }
    }
}
