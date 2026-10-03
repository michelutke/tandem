import Foundation

/// Agent side of the Share extension queue: starts one `FileOffer` per queued file, in order, and
/// deletes each App Group copy when its transfer ends (PRD F-7.2).
public final class SendRequestAgent: Sendable {
    private let queue: SendRequestQueue
    private let transfer: any FileTransferService

    public init(queue: SendRequestQueue, transfer: any FileTransferService) {
        self.queue = queue
        self.transfer = transfer
    }

    /// Number of offers started. Leaves the queue untouched while no peer is connected.
    @discardableResult
    public func drain() async -> Int {
        guard transfer.isConnected else { return 0 }
        var started = 0
        for request in queue.dequeue() {
            for copy in request {
                await transfer.startOffer(for: copy)
                started += 1
            }
        }
        return started
    }

    /// Call when a transfer ends (completed, rejected or cancelled).
    public func transferEnded(copy: URL) {
        queue.discard(copy: copy)
    }
}
