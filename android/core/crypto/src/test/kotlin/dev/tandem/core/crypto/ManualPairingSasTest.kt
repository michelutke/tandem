package dev.tandem.core.crypto

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** `protocol/vectors/manual-pairing.json` (E73-02) against [ManualPairingSas] (E73-03, ADR-008). */
class ManualPairingSasTest {
    @Test
    fun manualPairingSas_everySasVector_derivesExpectedCommitmentsAndSixDigits() {
        val entries = vectors("sas")
        assertTrue(entries.isNotEmpty())
        for (entry in entries) {
            val input = entry.input()
            val context = context(input)
            val expected = entry.getValue("expected").jsonObject
            val noncePhone = hex(input, "noncePhoneHex")
            val nonceMac = hex(input, "nonceMacHex")
            assertEquals(
                expected.getValue("sas").jsonPrimitive.content,
                ManualPairingSas.sas(noncePhone, nonceMac, context),
            )
            assertEquals(
                expected.getValue("commitPhoneHex").jsonPrimitive.content,
                ManualPairingSas.commitment(ManualPairingSas.Role.PHONE, noncePhone, context).toHex(),
            )
            assertEquals(
                expected.getValue("commitMacHex").jsonPrimitive.content,
                ManualPairingSas.commitment(ManualPairingSas.Role.MAC, nonceMac, context).toHex(),
            )
        }
    }

    @Test
    fun manualPairingSas_everyCommitmentVector_verifiesOnlyMatchingReveals() {
        val entries = vectors("commitment")
        assertTrue(entries.isNotEmpty())
        for (entry in entries) {
            val input = entry.input()
            val role =
                if (input.getValue("committerRole").jsonPrimitive.content == "phone") {
                    ManualPairingSas.Role.PHONE
                } else {
                    ManualPairingSas.Role.MAC
                }
            val verified =
                ManualPairingSas.verifyCommitment(
                    hex(input, "commitmentHex"),
                    role,
                    hex(input, "revealNonceHex"),
                    context(input),
                )
            assertEquals("expectedError" !in entry, verified, entry.getValue("id").jsonPrimitive.content)
        }
    }

    @Test
    fun manualPairingSas_malformedNonceOrCommitmentLength_neverVerifies() {
        val input = vectors("sas").first().input()
        assertFalse(
            ManualPairingSas.verifyCommitment(
                ByteArray(32),
                ManualPairingSas.Role.PHONE,
                ByteArray(15),
                context(input),
            ),
        )
        assertFalse(
            ManualPairingSas.verifyCommitment(
                ByteArray(31),
                ManualPairingSas.Role.PHONE,
                ByteArray(16),
                context(input),
            ),
        )
    }

    private fun vectors(kind: String): List<JsonObject> {
        val dir = System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        return Json
            .parseToJsonElement(File(dir, "manual-pairing.json").readText())
            .jsonObject
            .getValue("vectors")
            .jsonArray
            .map { it.jsonObject }
            .filter {
                it
                    .input()
                    .getValue("kind")
                    .jsonPrimitive.content == kind
            }
    }

    private fun JsonObject.input(): JsonObject = getValue("input").jsonObject

    private fun hex(
        input: JsonObject,
        key: String,
    ): ByteArray =
        input
            .getValue(key)
            .jsonPrimitive.content
            .hexToByteArray()

    private fun context(input: JsonObject) =
        ManualPairingContext(hex(input, "macSpkiDerHex"), hex(input, "phoneSpkiDerHex"), hex(input, "cbHex"))

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private fun String.hexToByteArray(): ByteArray =
        ByteArray(length / 2) { substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}
