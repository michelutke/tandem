package dev.tandem.core.crypto

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Shared helper for reading `protocol/vectors/spki-fingerprint.json` (E01-17), used by
 * [SpkiFingerprintTest] (E10-03). Path wired via the `tandem.vectorsDir` system property
 * (android/core/crypto/build.gradle.kts), mirroring `core/protocol`'s `FrameVectorTestSupport`.
 */
fun loadSpkiFingerprintVectorsFile(): JsonObject {
    val vectorsDir =
        System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
    val file = File(vectorsDir, "spki-fingerprint.json")
    return Json.parseToJsonElement(file.readText()).jsonObject
}

fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
