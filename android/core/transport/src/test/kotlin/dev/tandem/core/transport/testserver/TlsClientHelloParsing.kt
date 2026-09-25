package dev.tandem.core.transport.testserver

/** TLS 1.3 `pre_shared_key` extension type (RFC 8446 §4.2.11). */
const val EXTENSION_TYPE_PRE_SHARED_KEY = 0x0029

/** TLS 1.3 `early_data` extension type (RFC 8446 §4.2.10). */
const val EXTENSION_TYPE_EARLY_DATA = 0x002a

/**
 * Parses the extension types offered in a single captured plaintext TLS record containing a
 * `ClientHello` handshake message (RFC 8446 §4.1.2), so `integration:` tests can assert the wire
 * bytes directly rather than relying on JSSE/Conscrypt to expose resumption state — no public API
 * on either stack reports "this ClientHello offered a PSK" once the handshake completes.
 */
fun clientHelloExtensionTypes(record: ByteArray): Set<Int> {
    require(record.size >= RECORD_HEADER_SIZE) { "record too short for a TLS record header" }
    require(record[0] == HANDSHAKE_CONTENT_TYPE) { "not a handshake record" }

    val recordLength = readUInt16(record, 3)
    val body = record.copyOfRange(RECORD_HEADER_SIZE, RECORD_HEADER_SIZE + recordLength)
    require(body[0] == CLIENT_HELLO_MESSAGE_TYPE) { "not a ClientHello handshake message" }

    var offset = 4 // handshake type (1) + handshake length (3)
    offset += 2 // legacy_version
    offset += 32 // random
    val sessionIdLength = body[offset].toInt() and 0xFF
    offset += 1 + sessionIdLength
    val cipherSuitesLength = readUInt16(body, offset)
    offset += 2 + cipherSuitesLength
    val compressionMethodsLength = body[offset].toInt() and 0xFF
    offset += 1 + compressionMethodsLength
    val extensionsLength = readUInt16(body, offset)
    offset += 2

    val extensionsEnd = offset + extensionsLength
    val types = mutableSetOf<Int>()
    while (offset < extensionsEnd) {
        val type = readUInt16(body, offset)
        val length = readUInt16(body, offset + 2)
        types += type
        offset += 4 + length
    }
    return types
}

private const val RECORD_HEADER_SIZE = 5
private val HANDSHAKE_CONTENT_TYPE = 0x16.toByte()
private val CLIENT_HELLO_MESSAGE_TYPE = 0x01.toByte()

private fun readUInt16(
    bytes: ByteArray,
    offset: Int,
): Int = ((bytes[offset].toInt() and 0xFF) shl 8) or (bytes[offset + 1].toInt() and 0xFF)
