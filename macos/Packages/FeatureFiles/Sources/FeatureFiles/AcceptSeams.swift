import Foundation

/// Free bytes on the volume holding a transfer's destination.
public protocol FreeSpaceProvider: Sendable {
    func availableBytes(at destination: URL) -> UInt64
}

/// Production ``FreeSpaceProvider`` over `volumeAvailableCapacityForImportantUsageKey`. A destination
/// that does not exist yet (`~/Downloads/Tandem` before the first receive) is measured through its
/// nearest existing ancestor, which sits on the same volume.
public struct VolumeFreeSpaceProvider: FreeSpaceProvider {
    public init() {}

    public func availableBytes(at destination: URL) -> UInt64 {
        var url = destination
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
    }
}

/// The user's answer to an accept prompt (notification actions Accept / Decline).
public struct AcceptPromptResponse: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case accept
        case decline
    }

    public let offerId: String
    public let decision: Decision

    public init(offerId: String, decision: Decision) {
        self.offerId = offerId
        self.decision = decision
    }
}

/// Seam over `UNUserNotificationCenter` for the Accept / Decline prompt.
public protocol AcceptPromptPresenter: Sendable {
    func present(offerId: String, displayName: String, size: UInt64) async
    func remove(offerId: String) async
    var responses: AsyncStream<AcceptPromptResponse> { get }
}

public struct AcceptSettings: Sendable, Equatable {
    public var autoAcceptEnabled: Bool
    public var autoAcceptMaxSize: UInt64

    public init(autoAcceptEnabled: Bool = false, autoAcceptMaxSize: UInt64 = 1 << 30) {
        self.autoAcceptEnabled = autoAcceptEnabled
        self.autoAcceptMaxSize = autoAcceptMaxSize
    }
}
