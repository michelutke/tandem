import Observation

/// The currently paired peer's display name, republished from ``TrustStore`` whenever pairing
/// commits or the peer is unpaired, so the menu bar never shows a stale paired state.
@MainActor
@Observable
public final class PairedPeerState {
    public private(set) var displayName: String?
    public private(set) var record: PeerRecord?

    @ObservationIgnored
    private let trustStore: TrustStore

    public init(trustStore: TrustStore) {
        self.trustStore = trustStore
        record = Self.firstRecord(in: trustStore)
        displayName = record?.displayName
    }

    public func refresh() {
        record = Self.firstRecord(in: trustStore)
        displayName = record?.displayName
    }

    private static func firstRecord(in trustStore: TrustStore) -> PeerRecord? {
        (try? trustStore.list())?.first
    }
}
