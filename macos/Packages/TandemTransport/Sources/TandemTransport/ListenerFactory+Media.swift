import Foundation
import Network
import TandemCrypto
import TandemProtocol

extension NWListenerFactory {
    /// Classifies a freshly Ready connection by its first frame (E60-03, SPEC.md § Media ticket):
    /// a control `Envelope` returns `true` with the bytes pushed back for the multiplexer; anything
    /// else goes to ``mediaConnectionHandler`` and returns `false`. A no-op returning `true` when
    /// no handler is configured. Nothing is read beyond the first frame, so no application data is
    /// processed before the handler (and its ticket check) has the connection.
    func routeFirstFrame(
        adapter: NWConnectionByteStreamConnection,
        source: ByteStreamConnectionFrameSource,
        metadataIdentifier: ObjectIdentifier
    ) async -> Bool {
        guard let handler = mediaConnectionHandler else { return true }
        let outcome = await FirstFrameReader.read(from: source, clock: clock, onDeadline: { adapter.cancel() })
        guard case .frame(let body, let wire) = outcome else {
            adapter.cancel()
            abandonIfPairingCandidate(decisionCorrelator.drop(metadataIdentifier: metadataIdentifier))
            return false
        }
        let replay = wire + source.takeBuffered()
        if case .envelope = FirstFrameClassifier.classify(body: body) {
            source.pushBack(replay)
            return true
        }
        guard let recorded = decisionCorrelator.take(metadataIdentifier: metadataIdentifier) else {
            adapter.cancel()
            return false
        }
        let connection = PrefixedByteStreamConnection(adapter, prefix: replay)
        switch recorded.decision {
        case .trusted:
            guard let fingerprint = recorded.fingerprint else { adapter.cancel(); return false }
            await handler.handle(connection: connection, peer: .trusted(fingerprint))
        case .pairingCandidate:
            abandonIfPairingCandidate(recorded)
            await handler.handle(connection: connection, peer: .pairingCandidate)
        case .rejected:
            adapter.cancel()
        }
        return false
    }
}
