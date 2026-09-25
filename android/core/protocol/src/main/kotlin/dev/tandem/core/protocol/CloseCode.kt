package dev.tandem.core.protocol

/**
 * Protocol-level close codes (SPEC.md #errors-and-close-codes, E01-05): "the single canonical
 * enumeration of protocol-level close codes... no other part of this document or the codebase
 * may introduce a new close code outside this table." No generated `CloseCode` type exists yet
 * (status.proto does not define one); this enumerates only the row [FrameDecoder] (E11-02) can
 * produce. Other rows are added by whichever issue first needs to produce them (e.g. the channel
 * multiplexer's `CREDIT_VIOLATION`, E11-07), never renumbered or reused once released.
 */
enum class CloseCode {
    MALFORMED_FRAME,
}
