package dev.tandem.core.protocol.multiplex

/**
 * Thrown by [ChannelMultiplexer.send] once [ChannelMultiplexer.closeReason] has completed (E11-05;
 * aligned with the macOS twin, E11-06's `MultiplexerError.closed(MultiplexerClose)`): there is no
 * connection left to write [close]'s frame onto.
 */
class MultiplexerClosedException(
    val close: MultiplexerClose,
) : Exception("ChannelMultiplexer is closed: $close")
