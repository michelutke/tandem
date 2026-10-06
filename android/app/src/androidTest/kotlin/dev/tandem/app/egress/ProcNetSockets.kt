package dev.tandem.app.egress

import java.net.InetAddress

/** One row of `/proc/net/{tcp,tcp6,udp,udp6}`. */
internal data class ProcNetSocket(
    val uid: Int,
    val remoteAddress: String,
    val remotePort: Int,
)

/** Parses `/proc/net/{tcp,tcp6,udp,udp6}` dumps (E71-14); remote addresses come back in dotted or textual form. */
internal object ProcNetSockets {
    private const val UID_COLUMN = 7
    private const val REMOTE_COLUMN = 2
    private const val IPV4_HEX_LENGTH = 8
    private const val RADIX = 16

    fun parse(dump: String): List<ProcNetSocket> =
        dump
            .lineSequence()
            .map { it.trim().split(Regex("\\s+")) }
            .filter { columns -> columns.size > UID_COLUMN && columns[0].endsWith(":") && columns[0] != "sl" }
            .map { columns ->
                val (address, port) = columns[REMOTE_COLUMN].split(":")
                ProcNetSocket(columns[UID_COLUMN].toInt(), decodeAddress(address), port.toInt(RADIX))
            }.toList()

    private fun decodeAddress(hex: String): String {
        val wordBytes = hex.chunked(IPV4_HEX_LENGTH).flatMap { word -> word.chunked(2).reversed() }
        val bytes = ByteArray(wordBytes.size) { wordBytes[it].toInt(RADIX).toByte() }
        return InetAddress.getByAddress(bytes).hostAddress.orEmpty()
    }
}
