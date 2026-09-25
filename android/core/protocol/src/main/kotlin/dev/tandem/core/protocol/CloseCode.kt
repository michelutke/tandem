package dev.tandem.core.protocol

/**
 * Protocol-level close codes (SPEC.md #errors-and-close-codes, E01-05): "the single canonical
 * enumeration of protocol-level close codes... no other part of this document or the codebase
 * may introduce a new close code outside this table." No generated `CloseCode` type exists yet
 * (status.proto does not define one); this enumerates the rows produced so far: [FrameDecoder]
 * (E11-02) produces [MALFORMED_FRAME], [dev.tandem.core.protocol.multiplex.ChannelMultiplexer]
 * (E11-07) produces [CREDIT_VIOLATION] (SPEC.md #channels-and-flow-control-credits, D-64), and
 * [dev.tandem.core.protocol.connection.ConnectionStateMachine] (E12-08) produces
 * [PROTOCOL_TIMEOUT] for its 10 s TLS-handshake deadline (SPEC.md
 * #timeouts-connection-limits-and-resource-caps, E01-22). Other rows are added by whichever issue
 * first needs to produce them, never renumbered or reused once released.
 */
enum class CloseCode {
    MALFORMED_FRAME,
    CREDIT_VIOLATION,
    PROTOCOL_TIMEOUT,
}
