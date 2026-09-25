package dev.tandem.core.crypto

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * Shared helper for reading `protocol/vectors/pairing-proof.json` (E01-18), used by
 * [PairingProofTest] (E10-12). Path wired via the `tandem.vectorsDir` system property
 * (android/core/crypto/build.gradle.kts), mirroring `SpkiFingerprintVectorTestSupport`.
 */
fun loadPairingProofVectorsFile(): JsonObject {
    val vectorsDir =
        System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
    val file = File(vectorsDir, "pairing-proof.json")
    return Json.parseToJsonElement(file.readText()).jsonObject
}

/** `proof`-kind entries of the manifest (SPEC.md #2 Proof computation). */
fun proofVectors(): List<JsonObject> =
    loadPairingProofVectorsFile()
        .getValue("vectors")
        .jsonArray
        .map { it.jsonObject }
        .filter {
            it
                .getValue("input")
                .jsonObject
                .getValue("kind")
                .jsonPrimitive.content == "proof"
        }

/** `code`-kind entries of the manifest (SPEC.md #2 Confirmation code). */
fun codeVectors(): List<JsonObject> =
    loadPairingProofVectorsFile()
        .getValue("vectors")
        .jsonArray
        .map { it.jsonObject }
        .filter {
            it
                .getValue("input")
                .jsonObject
                .getValue("kind")
                .jsonPrimitive.content == "code"
        }
