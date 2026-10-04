import Foundation

/// Minimal async byte-source abstraction ``FrameDecoder`` reads from. `TandemProtocol` must not
/// depend on `TandemTransport` (PRD module rules: transport depends on protocol, never the
/// reverse), so this is not `ByteStreamConnection` (E00-25) itself; `TandemTransport`'s real
/// `NWConnection` adapter (E12-12) and tests' `InMemoryConnectionPair` (`TandemTestSupport`) both
/// adapt to this protocol instead of this package depending on either.
public protocol FrameSource: Sendable {
    /// Reads until exactly `count` bytes have been collected, or until the underlying stream
    /// closes first — in which case it returns everything collected so far for this call, which
    /// may be fewer than `count` bytes, including zero. ``FrameDecoder`` distinguishes a clean
    /// connection close (zero bytes into a new frame) from a `TRUNCATED` rejection (one or more
    /// bytes into a frame, then closure) using this returned count
    /// (docs/protocol/SPEC.md #framing-and-envelope). A transport-level error (e.g. a TCP reset)
    /// MUST be reported by throwing, never through a short read (SPEC.md's `TRUNCATED` row: "A
    /// TCP reset (RST) is a transport-layer error, not a framing rejection").
    func read(exactly count: Int) async throws -> Data
}

/// The canonical protocol-level close codes (docs/protocol/SPEC.md #errors-and-close-codes,
/// E01-05: "the single canonical enumeration ... no other part of this document or the codebase
/// may introduce a new close code outside this table"). `TandemProtocol` has no generated
/// `CloseCode` type to reuse yet (`protocol/proto/tandem/v1/status.proto` does not define one as
/// of this issue); this local enum is grown one case at a time, only as the issue implementing
/// that row needs it -- it is not yet the full nine-row table.
public enum CloseCode: Sendable, Equatable {
    case malformedFrame
    /// A peer violated the credit-flow-control contract (docs/protocol/SPEC.md
    /// #channels-and-flow-control-credits; `docs/planning/decisions.md` D-64): it transmitted a
    /// frame on a feature channel past the credit this side had granted it, or it sent a
    /// `CreditGrant` naming an amount that would take this side's own send balance for that
    /// channel above the channel's cap. Detected by ``ChannelMultiplexer`` (E11-08), never by
    /// ``FrameDecoder`` itself -- framing decode has no notion of per-channel credit.
    case creditViolation
    /// SPEC.md #errors-and-close-codes row 2, `PIN_MISMATCH`: the TLS verify callback (§1,
    /// E01-01) computes a peer SPKI fingerprint that does not match the trust store, outside an
    /// open pairing window (`PeerAuthorizer/decide(spki:trustStore:window:)`'s `.rejected`
    /// outcome, E12-02). SPEC.md's row 2 text covers both a previously-unknown peer and one whose
    /// key changed from a still-pinned entry ("this device's identity changed / is not trusted");
    /// which of those two applies is presentation-layer context (whether the peer's name is
    /// already known), never a second close code (E01-05: "no other part of ... the codebase may
    /// introduce a new close code outside this table"). SPEC.md's "Pre-authentication closes are
    /// not surfaced per connection" also applies to this row: an unrecognized-key connection that
    /// never passed the pin check (no open pairing window) MUST NOT pop a per-attempt UI
    /// notification, only an aggregate counter -- not yet wired to any production caller as of
    /// this issue (E22-07 delivers the presentation-layer `ErrorBannerViewModel` only).
    case pinMismatch
    /// The `VersionHello` protocol major version fields exchanged per §6 differ (SPEC.md row 1,
    /// E01-06). Detected by ``VersionHandshake`` (E12-07), reported to ``ConnectionStateMachine``
    /// (E12-09) as the reason a hello-stage handshake failed.
    case versionMismatch
    /// A deadline in §10 elapsed without the required message (SPEC.md row 8, E01-22): the TLS
    /// handshake deadline (``ConnectionStateMachine/handshakeDeadline``, E12-09) or the
    /// `VersionHello` deadline (``VersionHandshake/helloDeadline``, E12-07).
    case protocolTimeout
    /// A peer or source exceeds a connection-level cap in SPEC.md §10 (E01-22), or an older
    /// control session is replaced by a newer Ready session for the same peer SPKI (E12-19).
    case limitExceeded
    /// SPEC.md #errors-and-close-codes row 6, `TICKET_REJECTED`: the media connection's `MediaHello`
    /// ticket was missing, reused, expired, or issued to a different peer (E60-03). Closes the media
    /// connection only; never the control session that issued the ticket.
    case ticketRejected
}

/// Local diagnostic reason grouped under `CloseCode.malformedFrame`. Never sent on the wire
/// (docs/protocol/SPEC.md #framing-and-envelope "Rejection cases" / #errors-and-close-codes
/// "Local reason vs. wire code", `docs/planning/decisions.md` D-13). Swift counterpart to
/// Android's `FrameDecoder` reasons (E11-02).
public enum MalformedFrameReason: Sendable, Equatable {
    case tooLarge
    case badLength
    case truncated
    case decodeFailed
    case unknownChannel
    case unknownPayloadType
    /// A `seq`/`ack` watermark violation (`docs/planning/decisions.md` D-57): a `seq` of 0, at or
    /// below the current ack watermark for that channel, a duplicate of an already-received
    /// above-watermark value, or an `ack` above the highest `seq` this side has itself sent on
    /// that channel. Detected by ``ChannelMultiplexer`` (E11-06), not by ``FrameDecoder`` itself
    /// -- framing decode has no notion of per-channel state -- but grouped under this same
    /// `CloseCode.malformedFrame` per D-57, so it lives alongside the other local reasons here.
    case seqRegression
    /// A channel's above-watermark `seq` gap grew past ``CreditCaps/protocolMax`` (D-64): a
    /// legitimate peer, bound by its receive credit, can never have this many `seq` values
    /// outstanding above the watermark at once, so this is a fatal violation rather than another
    /// accepted gap-fill. Detected by ``ChannelMultiplexer`` (E11-06) alongside `seqRegression`.
    case seqGapTooLarge
}

/// The outcome of decoding one frame: either the `Envelope` it carried, or a rejection with its
/// close code and local reason. Nothing is emitted on rejection (SPEC.md #framing-and-envelope).
enum DecodeResult: Sendable, Equatable {
    case frame(Tandem_V1_Envelope)
    case rejected(CloseCode, MalformedFrameReason)
}

/// Decodes one frame from a ``FrameSource``: a 4-byte big-endian length prefix followed by
/// exactly that many bytes of serialized `Envelope`, the inverse of `FrameEncoder`'s wire format
/// (docs/protocol/SPEC.md #framing-and-envelope). Swift counterpart to the Android `FrameDecoder`
/// (E11-02). `Tandem_V1_Envelope` is internal to this module (the generated code is not built
/// with `Visibility=Public`), so this stays internal too.
enum FrameDecoder {
    /// `decode(from:)` returns `nil` when the source closes with zero bytes into a new frame —
    /// an ordinary connection close at a frame boundary, not a rejection
    /// (docs/protocol/SPEC.md #framing-and-envelope: "An orderly close ... that arrives exactly
    /// at a frame boundary ... is a normal, non-error connection close, not a `TRUNCATED`
    /// violation."). Any other error (e.g. a transport failure) propagates by throwing.
    static func decode(from source: FrameSource) async throws -> DecodeResult? {
        let prefixBytes = try await source.read(exactly: 4)
        guard prefixBytes.count == 4 else {
            return prefixBytes.isEmpty ? nil : .rejected(.malformedFrame, .truncated)
        }

        let prefix = [UInt8](prefixBytes)
        let length =
            UInt32(prefix[0]) << 24 | UInt32(prefix[1]) << 16 | UInt32(prefix[2]) << 8 | UInt32(prefix[3])

        // Checked, and rejected using only these 4 prefix bytes, before allocating or reading
        // anything sized from the attacker-supplied length (SPEC.md #framing-and-envelope).
        guard length <= UInt32(FrameEncoder.maxEnvelopeBytes) else {
            return .rejected(.malformedFrame, .tooLarge)
        }
        guard length > 0 else {
            return .rejected(.malformedFrame, .badLength)
        }

        let envelopeBytes = try await source.read(exactly: Int(length))
        guard envelopeBytes.count == Int(length) else {
            // The frame already started (the prefix fully arrived), so any closure here — even
            // with zero envelope bytes collected — is a truncation, not a clean boundary.
            return .rejected(.malformedFrame, .truncated)
        }

        let envelope: Tandem_V1_Envelope
        do {
            envelope = try Tandem_V1_Envelope(serializedBytes: envelopeBytes)
        } catch {
            return .rejected(.malformedFrame, .decodeFailed)
        }

        switch envelope.channel {
        case .unspecified, .UNRECOGNIZED:
            return .rejected(.malformedFrame, .unknownChannel)
        case .control, .notify, .clipboard, .files, .sms, .contacts, .calls, .input, .status:
            break
        }

        guard envelope.payload != nil else {
            return .rejected(.malformedFrame, .unknownPayloadType)
        }

        return .frame(envelope)
    }
}
