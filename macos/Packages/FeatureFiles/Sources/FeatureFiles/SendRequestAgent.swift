import Foundation

/// Agent side of the Share extension queue: starts one `FileOffer` per queued file, in order, and
/// deletes each App Group copy when its transfer ends (PRD F-7.2).
public final class SendRequestAgent: @unchecked Sendable {
    private let queue: SendRequestQueue
    private let transfer: any FileTransferService
    private let lock = NSLock()
    private var offered: Set<URL> = []

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
            for copy in request where markOffered(copy) {
                let didStart = await transfer.startOffer(for: copy) { [weak self] in self?.transferEnded(copy: copy) }
                if didStart {
                    started += 1
                } else {
                    unmarkOffered(copy)
                }
            }
        }
        return started
    }

    /// Call when a transfer ends (completed, rejected or cancelled).
    public func transferEnded(copy: URL) {
        queue.discard(copy: copy)
        _ = lock.withLock { offered.remove(copy) }
    }

    private func unmarkOffered(_ copy: URL) {
        _ = lock.withLock { offered.remove(copy) }
    }

    private func markOffered(_ copy: URL) -> Bool {
        lock.withLock { offered.insert(copy).inserted }
    }
}
