package com.tandem.spike.e2ehandshake

import java.io.InputStream
import java.io.OutputStream
import java.security.Signature
import javax.net.ssl.SSLSocket

/**
 * E03-04 experiment 2: the API 29/30 fallback for D-15's channel binding when
 * `android.net.ssl.SSLSockets.exportKeyingMaterial` (API 31+ only, per E03-03's finding) is
 * unavailable. Instead of an RFC 9266 exporter, the verifier (the macOS listener here) sends 32
 * random bytes over the already-established, mutually-authenticated TLS session; this side signs
 * them with the same AndroidKeyStore private key already used for the TLS client certificate and
 * sends the signature back. The signature only proves anything because it travels inside the one
 * live, pinned TLS session the challenge came from -- see docs/spikes/channel-binding.md for the
 * security argument.
 */
object ChallengeClient {

    data class ChallengeResult(
        val challengeSha256Hex: String,
        val ackOk: Boolean,
        val latencyMs: Long,
    )

    /** Reads exactly [length] bytes or throws -- `InputStream.read` may return short reads. */
    private fun readExact(input: InputStream, length: Int): ByteArray {
        val buffer = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val n = input.read(buffer, offset, length - offset)
            if (n < 0) error("stream closed after $offset/$length bytes")
            offset += n
        }
        return buffer
    }

    /** Performs one challenge/response round trip on an already-handshaken [socket]. */
    fun respond(socket: SSLSocket, alias: String): ChallengeResult {
        val start = System.nanoTime()
        val input = socket.inputStream
        val output = socket.outputStream

        val challenge = readExact(input, 32)

        val signature = Signature.getInstance("SHA256withECDSA").apply {
            initSign(KeystoreIdentity.privateKey(alias))
            update(challenge)
        }.sign()

        require(signature.size in 1..255) { "signature length ${signature.size} does not fit in one length byte" }
        output.write(byteArrayOf(signature.size.toByte()))
        output.write(signature)
        output.flush()

        val ack = readExact(input, 1)
        val elapsedMs = (System.nanoTime() - start) / 1_000_000

        return ChallengeResult(
            challengeSha256Hex = sha256Hex(challenge),
            ackOk = ack[0] == 0x01.toByte(),
            latencyMs = elapsedMs,
        )
    }

    private fun sha256Hex(data: ByteArray): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(data)
        return digest.joinToString("") { "%02x".format(it) }
    }
}
