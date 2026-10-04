import Network
import TandemCrypto
import TandemProtocol

extension NWListenerFactory {
    /// A connection that never reaches `.ready` (verify rejected it, or it reset/timed out first)
    /// may still have a decision recorded for it (E12-02's `onDecision` fires before `complete(_:)`
    /// regardless of outcome) -- drop it so a *later* connection can never inherit a stale
    /// `.trusted` decision through a reused `sec_protocol_metadata_t` `ObjectIdentifier` (finding
    /// #3: the address-reuse race this guards against). Returns the dropped entry, if any, so the
    /// caller can still release a `.pairingCandidate` connection's window slot (E14-16 finding #1).
    @discardableResult
    static func dropStaleDecision(
        connection: NWConnection,
        decisionCorrelator: PeerDecisionCorrelator
    ) -> PeerDecisionCorrelator.Decision? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        return decisionCorrelator.drop(metadataIdentifier: ObjectIdentifier(metadata.securityProtocolMetadata))
    }
}

extension VersionHandshake.HandshakeFailure {
    var closeCode: CloseCode {
        switch self {
        case .versionMismatch: .versionMismatch
        case .protocolTimeout: .protocolTimeout
        }
    }
}
