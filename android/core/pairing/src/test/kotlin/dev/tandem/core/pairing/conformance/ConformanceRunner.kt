package dev.tandem.core.pairing.conformance

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ConfirmationCode
import dev.tandem.core.crypto.PairingProof
import dev.tandem.core.crypto.PairingProofException
import dev.tandem.core.crypto.SpkiFingerprintException
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.pairing.qr.InviteError
import dev.tandem.core.pairing.qr.ParseInviteResult
import dev.tandem.core.pairing.qr.QrPayloadParser
import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.DisplayStringKind
import dev.tandem.core.protocol.DisplayStringSanitizer
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.protocol.v1.ClipboardText
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.FileAccept
import dev.tandem.protocol.v1.FileChunk
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.FileReject
import dev.tandem.protocol.v1.FileResumeRequest
import dev.tandem.protocol.v1.clipboardText
import dev.tandem.protocol.v1.fileChunk
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File

/** One vector's result: `"pass"`, `"fail"`, or `"skipped"` (a deferred / not-applicable category). */
data class VectorOutcome(
    val id: String,
    val category: String,
    val outcome: String,
    val expected: String,
    val actual: String,
)

/** A category present on disk under `protocol/vectors/` that this runner's table does not know. */
class UnknownVectorCategoryException(
    category: String,
) : RuntimeException("unknown vector category on disk: $category")

/** Thrown by [ConformanceRunner.assertAllPassed] naming every failing vector, hex included. */
class ConformanceFailure(
    message: String,
) : RuntimeException(message)

/**
 * E15-01: aggregates every `protocol/vectors/` category against the real Kotlin codec/crypto
 * implementations behind one explicit category -> handler table. A category on disk that is not
 * in this table is an error, never a silent skip ([UnknownVectorCategoryException]).
 * [deferredCategories] names the categories this platform cannot run yet, and the issue that will
 * add them.
 *
 * Lives in `core/pairing`'s test source set because that is the one Gradle module already
 * depending on `core/protocol` (frame codec, display-string sanitizer), `core/crypto` (SPKI
 * fingerprint, pairing proof / confirmation code) and its own QR payload parser -- reusing that
 * existing dependency graph instead of adding a new Gradle module (KISS).
 */
object ConformanceRunner {
    val deferredCategories: Map<String, String> = emptyMap()
    private val handledCategories: Set<String> =
        setOf(
            "frame-encoding",
            "heartbeat",
            "spki-fingerprint",
            "pairing-proof",
            "qr-payload",
            "display-strings",
            "status-encoding",
            "notify-encoding",
            "clipboard-encoding",
            "discovery-id",
            "files-encoding",
            "photos-encoding",
            "contacts-encoding",
            "sms-encoding",
            "calls-encoding",
            "filenames",
        )

    /** CLIPBOARD channel's text cap (docs/protocol/SPEC.md #clipboard-channel): 1 MiB, 2^20. */
    private const val MAX_CLIPBOARD_TEXT_BYTES = 1_048_576

    /** Every vector entry across every manifest under [vectorsDir], on disk right now. */
    fun countVectorsOnDisk(vectorsDir: File): Int =
        manifestFiles(vectorsDir).sumOf {
            it.second
                .getValue("vectors")
                .jsonArray.size
        }

    fun run(vectorsDir: File): List<VectorOutcome> =
        manifestFiles(vectorsDir).flatMap { (category, manifest) ->
            when {
                category in deferredCategories -> deferredOutcomes(category, manifest)
                category in handledCategories -> runCategory(category, manifest)
                else -> throw UnknownVectorCategoryException(category)
            }
        }

    /** Throws [ConformanceFailure] naming every failing vector's id, category, expected and actual. */
    fun assertAllPassed(outcomes: List<VectorOutcome>) {
        val failures = outcomes.filter { it.outcome == "fail" }
        if (failures.isEmpty()) return
        val message =
            failures.joinToString("\n") {
                "${it.category}:${it.id} expected=${it.expected} actual=${it.actual}"
            }
        throw ConformanceFailure("${failures.size} conformance vector(s) failed:\n$message")
    }

    fun writeReport(
        outcomes: List<VectorOutcome>,
        reportFile: File,
    ) {
        reportFile.parentFile?.mkdirs()
        val json = Json { prettyPrint = true }
        reportFile.writeText(json.encodeToString(JsonElement.serializer(), toJson(outcomes)))
    }

    private fun toJson(outcomes: List<VectorOutcome>): JsonArray =
        buildJsonArray {
            outcomes.forEach { outcome ->
                add(
                    buildJsonObject {
                        put("vectorId", outcome.id)
                        put("category", outcome.category)
                        put("outcome", outcome.outcome)
                        put("expected", outcome.expected)
                        put("actual", outcome.actual)
                    },
                )
            }
        }

    private fun manifestFiles(vectorsDir: File): List<Pair<String, JsonObject>> =
        vectorsDir
            .listFiles { file -> file.isFile && file.extension == "json" }
            .orEmpty()
            .sortedBy { it.name }
            .mapNotNull { file ->
                val manifest = Json.parseToJsonElement(file.readText()).jsonObject
                val category = manifest["category"]?.jsonPrimitive?.content ?: return@mapNotNull null
                category to manifest
            }

    private fun deferredOutcomes(
        category: String,
        manifest: JsonObject,
    ): List<VectorOutcome> =
        manifest.getValue("vectors").jsonArray.map { vector ->
            val id =
                vector.jsonObject
                    .getValue("id")
                    .jsonPrimitive.content
            val reason = "not implemented: deferred to ${deferredCategories.getValue(category)}"
            VectorOutcome(id, category, "skipped", "", reason)
        }

    private fun runCategory(
        category: String,
        manifest: JsonObject,
    ): List<VectorOutcome> =
        manifest.getValue("vectors").jsonArray.map { it.jsonObject }.map { vector ->
            when (category) {
                "frame-encoding" -> frameEncodingOutcome(vector)
                "heartbeat" -> heartbeatOutcome(vector)
                "spki-fingerprint" -> spkiFingerprintOutcome(vector)
                "pairing-proof" -> pairingProofOutcome(vector)
                "qr-payload" -> qrPayloadOutcome(vector)
                "display-strings" -> displayStringsOutcome(vector)
                "status-encoding" -> statusEncodingOutcome(vector)
                "notify-encoding" -> notifyEncodingOutcome(vector)
                "clipboard-encoding" -> clipboardEncodingOutcome(vector)
                "discovery-id" -> discoveryIdOutcome(vector)
                else -> runDomainPayloadCategory(category, vector)
            }
        }

    /** FILES/CONTACTS-channel payload categories, split out of [runCategory] purely to keep that
     * function under this repo's `CyclomaticComplexMethod` detekt budget. */
    private fun runDomainPayloadCategory(
        category: String,
        vector: JsonObject,
    ): VectorOutcome =
        when (category) {
            "files-encoding" -> filesEncodingOutcome(vector)
            "photos-encoding" -> photosEncodingOutcome(vector)
            "contacts-encoding" -> contactsEncodingOutcome(vector)
            "sms-encoding" -> smsEncodingOutcome(vector)
            "calls-encoding" -> callsEncodingOutcome(vector)
            "filenames" -> filenamesOutcome(vector)
            else -> throw UnknownVectorCategoryException(category)
        }

    private fun frameEncodingOutcome(vector: JsonObject): VectorOutcome =
        runBlocking {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            if ("expected" in vector) {
                frameEncodingValidOutcome(id, input, vector.getValue("expected").jsonObject)
            } else {
                frameEncodingInvalidOutcome(id, input, vector)
            }
        }

    private suspend fun frameEncodingValidOutcome(
        id: String,
        input: JsonObject,
        expected: JsonObject,
    ): VectorOutcome {
        val inputFrame =
            if ("frameHex" in input) {
                hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
            } else {
                val envelopeBytes = buildEnvelopeFromRecipe(input.getValue("envelopeRecipe").jsonObject)
                FrameEncoder.encodeFrame(Envelope.parseFrom(envelopeBytes))
            }
        val decoded = FrameDecoder.decodeFrame(sourceFor(inputFrame))
        val frame =
            decoded as? DecodeResult.Frame
                ?: return VectorOutcome(id, "frame-encoding", "fail", inputFrame.toHex(), "rejected: $decoded")

        val outputFrame = FrameEncoder.encodeFrame(frame.envelope)
        val expectedSha = expected["frameSha256"]?.jsonPrimitive?.content
        val passed =
            if ("frameHex" in input) {
                inputFrame.contentEquals(outputFrame)
            } else {
                expectedSha == null || expectedSha == sha256Hex(outputFrame)
            }
        val expectedHex = expectedSha ?: inputFrame.toHex()
        val actualHex = expectedSha?.let { sha256Hex(outputFrame) } ?: outputFrame.toHex()
        return VectorOutcome(id, "frame-encoding", if (passed) "pass" else "fail", expectedHex, actualHex)
    }

    private suspend fun frameEncodingInvalidOutcome(
        id: String,
        input: JsonObject,
        vector: JsonObject,
    ): VectorOutcome {
        val frameBytes = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
        val decoded = FrameDecoder.decodeFrame(sourceFor(frameBytes))
        val rejected = decoded as? DecodeResult.Rejected
        val expectedClose = vector.getValue("closeCode").jsonPrimitive.content
        val expectedReason = vector.getValue("localReason").jsonPrimitive.content
        val passed =
            rejected != null && rejected.closeCode.name == expectedClose && rejected.reason.name == expectedReason
        val actual = if (rejected != null) "${rejected.closeCode.name}:${rejected.reason.name}" else decoded.toString()
        return VectorOutcome(
            id,
            "frame-encoding",
            if (passed) "pass" else "fail",
            "$expectedClose:$expectedReason",
            actual,
        )
    }

    private fun heartbeatOutcome(vector: JsonObject): VectorOutcome =
        runBlocking {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            if ("expected" in vector) {
                heartbeatValidOutcome(id, input, vector.getValue("expected").jsonObject)
            } else {
                heartbeatInvalidOutcome(id, input, vector)
            }
        }

    private suspend fun heartbeatValidOutcome(
        id: String,
        input: JsonObject,
        expected: JsonObject,
    ): VectorOutcome {
        val inputFrame = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
        val decoded = FrameDecoder.decodeFrame(sourceFor(inputFrame))
        val frame =
            decoded as? DecodeResult.Frame
                ?: return VectorOutcome(id, "heartbeat", "fail", inputFrame.toHex(), "rejected: $decoded")

        val outputFrame = FrameEncoder.encodeFrame(frame.envelope)
        val passed = inputFrame.contentEquals(outputFrame)
        return VectorOutcome(id, "heartbeat", if (passed) "pass" else "fail", inputFrame.toHex(), outputFrame.toHex())
    }

    private suspend fun heartbeatInvalidOutcome(
        id: String,
        input: JsonObject,
        vector: JsonObject,
    ): VectorOutcome {
        val frameBytes = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
        val decoded = FrameDecoder.decodeFrame(sourceFor(frameBytes))
        val rejected = decoded as? DecodeResult.Rejected
        val expectedClose = vector.getValue("closeCode").jsonPrimitive.content
        val expectedReason = vector.getValue("localReason").jsonPrimitive.content
        val passed =
            rejected != null && rejected.closeCode.name == expectedClose && rejected.reason.name == expectedReason
        val actual = if (rejected != null) "${rejected.closeCode.name}:${rejected.reason.name}" else decoded.toString()
        return VectorOutcome(
            id,
            "heartbeat",
            if (passed) "pass" else "fail",
            "$expectedClose:$expectedReason",
            actual,
        )
    }

    private fun spkiFingerprintOutcome(vector: JsonObject): VectorOutcome {
        val id = vector.getValue("id").jsonPrimitive.content
        val spkiDer =
            hexToBytes(
                vector
                    .getValue("input")
                    .jsonObject
                    .getValue("spkiDerHex")
                    .jsonPrimitive.content,
            )
        return if ("expected" in vector) {
            spkiFingerprintValidOutcome(id, spkiDer, vector.getValue("expected").jsonObject)
        } else {
            spkiFingerprintInvalidOutcome(id, spkiDer, vector.getValue("expectedError").jsonPrimitive.content)
        }
    }

    private fun spkiFingerprintValidOutcome(
        id: String,
        spkiDer: ByteArray,
        expected: JsonObject,
    ): VectorOutcome {
        val expectedHex = expected.getValue("fingerprintHex").jsonPrimitive.content
        val actualHex =
            try {
                spkiFingerprint(spkiDer).bytes.toHex()
            } catch (e: SpkiFingerprintException) {
                return VectorOutcome(id, "spki-fingerprint", "fail", expectedHex, "threw ${e::class.simpleName}")
            }
        val outcome = if (actualHex == expectedHex) "pass" else "fail"
        return VectorOutcome(id, "spki-fingerprint", outcome, expectedHex, actualHex)
    }

    private fun spkiFingerprintInvalidOutcome(
        id: String,
        spkiDer: ByteArray,
        expectedError: String,
    ): VectorOutcome {
        val actualError =
            try {
                spkiFingerprint(spkiDer)
                "no error thrown"
            } catch (e: SpkiFingerprintException) {
                when (e) {
                    is SpkiFingerprintException.UnsupportedPointEncoding -> "unsupportedPointEncoding"
                    is SpkiFingerprintException.UnsupportedKeyType -> "unsupportedKeyType"
                    is SpkiFingerprintException.MalformedSpki -> "malformedSpki"
                }
            }
        val outcome = if (actualError == expectedError) "pass" else "fail"
        return VectorOutcome(id, "spki-fingerprint", outcome, expectedError, actualError)
    }

    /** `secret`/`macSpkiDer`/`phoneSpkiDer`/`cb` bundled so the outcome functions below stay under detekt's
     * six-parameter limit. */
    private data class ProofInputs(
        val secret: ByteArray,
        val macSpkiDer: ByteArray,
        val phoneSpkiDer: ByteArray,
        val cb: ByteArray,
    )

    private fun pairingProofOutcome(vector: JsonObject): VectorOutcome {
        val id = vector.getValue("id").jsonPrimitive.content
        val input = vector.getValue("input").jsonObject
        val kind = input.getValue("kind").jsonPrimitive.content
        val inputs =
            ProofInputs(
                secret = hexToBytes(input.getValue("secretHex").jsonPrimitive.content),
                macSpkiDer = hexToBytes(input.getValue("macSpkiDerHex").jsonPrimitive.content),
                phoneSpkiDer = hexToBytes(input.getValue("phoneSpkiDerHex").jsonPrimitive.content),
                cb = hexToBytes(input.getValue("cbHex").jsonPrimitive.content),
            )

        return when {
            kind == "code" -> {
                confirmationCodeOutcome(id, vector, inputs)
            }

            "expected" in vector -> {
                val proof = hexToBytes(input.getValue("proofHex").jsonPrimitive.content)
                validProofOutcome(id, proof, inputs)
            }

            else -> {
                val proof = hexToBytes(input.getValue("proofHex").jsonPrimitive.content)
                val expectedError = vector.getValue("expectedError").jsonPrimitive.content
                invalidProofOutcome(id, proof, inputs, expectedError)
            }
        }
    }

    private fun confirmationCodeOutcome(
        id: String,
        vector: JsonObject,
        inputs: ProofInputs,
    ): VectorOutcome {
        val expectedCode =
            vector
                .getValue("expected")
                .jsonObject
                .getValue("code")
                .jsonPrimitive.content
        val actualCode = ConfirmationCode.compute(inputs.secret, inputs.macSpkiDer, inputs.phoneSpkiDer, inputs.cb)
        val outcome = if (actualCode == expectedCode) "pass" else "fail"
        return VectorOutcome(id, "pairing-proof", outcome, expectedCode, actualCode)
    }

    private fun validProofOutcome(
        id: String,
        proof: ByteArray,
        inputs: ProofInputs,
    ): VectorOutcome {
        val valid =
            try {
                PairingProof.verify(proof, inputs.secret, inputs.macSpkiDer, inputs.phoneSpkiDer, inputs.cb)
            } catch (e: PairingProofException) {
                return VectorOutcome(id, "pairing-proof", "fail", "valid=true", "threw ${e::class.simpleName}")
            }
        return VectorOutcome(id, "pairing-proof", if (valid) "pass" else "fail", "valid=true", "valid=$valid")
    }

    private fun invalidProofOutcome(
        id: String,
        proof: ByteArray,
        inputs: ProofInputs,
        expectedError: String,
    ): VectorOutcome {
        val actual =
            try {
                val valid = PairingProof.verify(proof, inputs.secret, inputs.macSpkiDer, inputs.phoneSpkiDer, inputs.cb)
                if (valid) "valid" else "proofMismatch"
            } catch (e: PairingProofException) {
                when (e) {
                    is PairingProofException.MalformedProof -> "malformedProof"
                    is PairingProofException.MalformedSpki -> "malformedSpki"
                    is PairingProofException.MalformedChannelBinding -> "malformedChannelBinding"
                }
            }
        val outcome = if (actual == expectedError) "pass" else "fail"
        return VectorOutcome(id, "pairing-proof", outcome, expectedError, actual)
    }

    private fun qrPayloadOutcome(vector: JsonObject): VectorOutcome {
        val id = vector.getValue("id").jsonPrimitive.content
        val uri =
            vector
                .getValue("input")
                .jsonObject
                .getValue("uri")
                .jsonPrimitive.content
        val result = QrPayloadParser.parse(uri)

        return if ("expected" in vector) {
            qrPayloadValidOutcome(id, result, vector.getValue("expected").jsonObject)
        } else {
            qrPayloadInvalidOutcome(id, result, vector.getValue("expectedError").jsonPrimitive.content)
        }
    }

    private fun qrPayloadValidOutcome(
        id: String,
        result: ParseInviteResult,
        expected: JsonObject,
    ): VectorOutcome {
        val accepted =
            result as? ParseInviteResult.Accepted
                ?: return VectorOutcome(id, "qr-payload", "fail", "accepted", "rejected: $result")

        val invite = accepted.invite
        val expectedFp = expected.getValue("fingerprintHex").jsonPrimitive.content
        val actualFp = invite.fingerprint.toHex()
        val passed =
            expectedFp == actualFp &&
                expected.getValue("secretHex").jsonPrimitive.content == invite.secret.toHex() &&
                expected.getValue("addresses").jsonArray.map { it.jsonPrimitive.content } == invite.addresses &&
                expected
                    .getValue("port")
                    .jsonPrimitive.content
                    .toInt() == invite.port &&
                macNameMatches(expected, invite.macName)
        return VectorOutcome(id, "qr-payload", if (passed) "pass" else "fail", expectedFp, actualFp)
    }

    private fun macNameMatches(
        expected: JsonObject,
        macName: String,
    ): Boolean {
        val expectedName = hexToBytes(expected.getValue("nameHex").jsonPrimitive.content).toString(Charsets.UTF_8)
        return expectedName == macName
    }

    private fun qrPayloadInvalidOutcome(
        id: String,
        result: ParseInviteResult,
        expectedError: String,
    ): VectorOutcome {
        val rejected = result as? ParseInviteResult.Rejected
        val actualError = rejected?.let { wireName(it.error) } ?: "accepted: $result"
        val outcome = if (actualError == expectedError) "pass" else "fail"
        return VectorOutcome(id, "qr-payload", outcome, expectedError, actualError)
    }

    private fun wireName(error: InviteError): String = error::class.simpleName!!.replaceFirstChar { it.lowercase() }

    private fun displayStringsOutcome(vector: JsonObject): VectorOutcome {
        val id = vector.getValue("id").jsonPrimitive.content
        val input = vector.getValue("input").jsonObject
        val raw = hexToBytes(input.getValue("rawUtf8Hex").jsonPrimitive.content)
        val kind =
            when (input.getValue("kind").jsonPrimitive.content) {
                "name" -> DisplayStringKind.NAME
                "title" -> DisplayStringKind.TITLE
                "body" -> DisplayStringKind.BODY
                else -> error("unsupported display-string kind")
            }
        val expected =
            vector
                .getValue("expected")
                .jsonObject
                .getValue("sanitized")
                .jsonPrimitive.content
        val actual = DisplayStringSanitizer.sanitize(raw, kind)
        return VectorOutcome(id, "display-strings", if (actual == expected) "pass" else "fail", expected, actual)
    }

    private fun statusEncodingOutcome(vector: JsonObject): VectorOutcome =
        frameRoundTripOutcome("status-encoding", vector)

    private fun notifyEncodingOutcome(vector: JsonObject): VectorOutcome =
        frameRoundTripOutcome("notify-encoding", vector)

    /** Decodes an Envelope frame and re-encodes it, checking the bytes round-trip identically.
     * Shared by every category whose vectors are complete frame-encoding round-trips rather than
     * a category-specific transform (status-encoding, notify-encoding). */
    private fun frameRoundTripOutcome(
        category: String,
        vector: JsonObject,
    ): VectorOutcome =
        runBlocking {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            val inputFrame = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
            val decoded = FrameDecoder.decodeFrame(sourceFor(inputFrame))
            val frame =
                decoded as? DecodeResult.Frame
                    ?: return@runBlocking VectorOutcome(
                        id,
                        category,
                        "fail",
                        inputFrame.toHex(),
                        "rejected: $decoded",
                    )

            val outputFrame = FrameEncoder.encodeFrame(frame.envelope)
            val passed = inputFrame.contentEquals(outputFrame)
            VectorOutcome(
                id,
                category,
                if (passed) "pass" else "fail",
                inputFrame.toHex(),
                outputFrame.toHex(),
            )
        }

    /** `clipboard-encoding` category (E31-01): decodes the raw `ClipboardText` message bytes each
     * vector describes (inlined as `clipboardTextHex`, or a compact `textRecipe` — see
     * protocol/vectors/README.md) with the real generated `ClipboardText` type, then validates
     * `text`'s byte length against the CLIPBOARD channel's 1,048,576-byte cap
     * (docs/protocol/SPEC.md #clipboard-channel). Deliberately does not go through
     * `FrameEncoder`/`FrameDecoder`: wrapping a boundary vector in a full `Envelope` frame would
     * make the "exactly 1 MiB text is accepted" vector self-contradictory against the frame's
     * own, unrelated 1 MiB length cap (see `clipboard-encoding.json`'s entry in
     * protocol/vectors/README.md). */
    private fun clipboardEncodingOutcome(vector: JsonObject): VectorOutcome {
        val id = vector.getValue("id").jsonPrimitive.content
        val input = vector.getValue("input").jsonObject
        val messageBytes = clipboardTextBytes(input)
        val decoded =
            try {
                ClipboardText.parseFrom(messageBytes)
            } catch (e: Exception) {
                return VectorOutcome(
                    id,
                    "clipboard-encoding",
                    "fail",
                    "decodable",
                    "failed to decode: ${e::class.simpleName}",
                )
            }
        val textByteLength = decoded.text.toByteArray(Charsets.UTF_8).size
        val accepted = textByteLength <= MAX_CLIPBOARD_TEXT_BYTES
        val decodedInfo = DecodedClipboardText(decoded, accepted, textByteLength)

        return if ("expected" in vector) {
            clipboardEncodingValidOutcome(id, input, vector.getValue("expected").jsonObject, decodedInfo)
        } else {
            val expectedError = vector.getValue("expectedError").jsonPrimitive.content
            val actual = if (accepted) "accepted" else "clipboardTextTooLarge"
            val outcome = if (actual == expectedError) "pass" else "fail"
            VectorOutcome(id, "clipboard-encoding", outcome, expectedError, actual)
        }
    }

    /** [decoded]/[accepted]/[textByteLength] bundled so the outcome functions below stay under
     * detekt's six-parameter limit. */
    private data class DecodedClipboardText(
        val decoded: ClipboardText,
        val accepted: Boolean,
        val textByteLength: Int,
    )

    private fun clipboardEncodingValidOutcome(
        id: String,
        input: JsonObject,
        expected: JsonObject,
        decodedInfo: DecodedClipboardText,
    ): VectorOutcome {
        val (decoded, accepted, textByteLength) = decodedInfo
        if (!accepted) {
            return VectorOutcome(id, "clipboard-encoding", "fail", "accepted", "rejected: clipboardTextTooLarge")
        }
        val expectedOriginTag = expected.getValue("originTag").jsonPrimitive.content
        val expectedContentHashHex = expected.getValue("contentHashHex").jsonPrimitive.content
        val expectedSensitive =
            expected
                .getValue("sensitive")
                .jsonPrimitive.content
                .toBoolean()
        val expectedTextByteLength =
            expected
                .getValue("textByteLength")
                .jsonPrimitive.content
                .toInt()

        var passed =
            decoded.originTag == expectedOriginTag &&
                decoded.contentHash.toByteArray().toHex() == expectedContentHashHex &&
                decoded.sensitive == expectedSensitive &&
                textByteLength == expectedTextByteLength

        expected["text"]?.jsonPrimitive?.content?.let { expectedText ->
            passed = passed && decoded.text == expectedText
        }
        val expectedSha = expected["clipboardTextSha256"]?.jsonPrimitive?.content
        if (expectedSha != null) {
            passed = passed && sha256Hex(decoded.toByteArray()) == expectedSha
        } else {
            input["clipboardTextHex"]?.jsonPrimitive?.content?.let { hex ->
                passed = passed && decoded.toByteArray().contentEquals(hexToBytes(hex))
            }
        }

        val expectedDescription = "originTag=$expectedOriginTag textByteLength=$expectedTextByteLength"
        val actualDescription = "originTag=${decoded.originTag} textByteLength=$textByteLength"
        return VectorOutcome(
            id,
            "clipboard-encoding",
            if (passed) "pass" else "fail",
            expectedDescription,
            actualDescription,
        )
    }

    private fun clipboardTextBytes(input: JsonObject): ByteArray {
        input["clipboardTextHex"]?.jsonPrimitive?.content?.let { return hexToBytes(it) }

        val recipe = input.getValue("textRecipe").jsonObject
        val fillByte = hexToBytes(recipe.getValue("fillByte").jsonPrimitive.content).first()
        val fillLength =
            recipe
                .getValue("fillLength")
                .jsonPrimitive.content
                .toInt()
        val fillChar = (fillByte.toInt() and BYTE_MASK).toChar()
        val text = String(CharArray(fillLength) { fillChar })

        return clipboardText {
            originTag = input.getValue("originTag").jsonPrimitive.content
            contentHash = ByteString.copyFrom(hexToBytes(input.getValue("contentHashHex").jsonPrimitive.content))
            this.text = text
            sensitive =
                input
                    .getValue("sensitive")
                    .jsonPrimitive.content
                    .toBoolean()
        }.toByteArray()
    }

    private const val BYTE_MASK = 0xFF
}
