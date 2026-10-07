import Observation

/// The currently paired peer's display name, republished from ``TrustStore`` whenever pairing
/// commits or the peer is unpaired, so the menu bar never shows a stale paired state.
@MainActor
@Observable
public final class PairedPeerState {
    public private(set) var displayName: String?

    @ObservationIgnored
    private let trustStore: TrustStore

    public init(trustStore: TrustStore) {
        self.trustStore = trustStore
        displayName = Self.firstPeerName(in: trustStore)
    }

    public func refresh() {
        displayName = Self.firstPeerName(in: trustStore)
    }

    private static func firstPeerName(in trustStore: TrustStore) -> String? {
        (try? trustStore.list())?.first?.displayName
    }
}
