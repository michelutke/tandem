package dev.tandem.core.pairing.conformance

import dev.tandem.core.crypto.DiscoveryRotatingId
import dev.tandem.core.protocol.DiscoveryTxtRecord
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/**
 * `discovery-id` category handler for [ConformanceRunner] (E21-05): exercises the rotating-id
 * advertiser side ([DiscoveryRotatingId], `core/crypto`) and receiver side
 * ([DiscoveryRotatingId.recognize], [DiscoveryTxtRecord.parse], `core/protocol`) against every
 * vector "kind" in `protocol/vectors/discovery-id.json`: `computeId`, `recognition`, `txtRecord` --
 * mirroring TandemProtocolTests' `ConformanceRunner+DiscoveryId.swift`. Lives in its own file
 * (rather than as members of [ConformanceRunner]) so that object stays under detekt's `LargeClass`
 * threshold.
 */
fun discoveryIdOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    return when (input.getValue("kind").jsonPrimitive.content) {
        "computeId" -> discoveryIdComputeIdOutcome(id, input, vector)
        "recognition" -> discoveryIdRecognitionOutcome(id, input, vector)
        "txtRecord" -> discoveryIdTxtRecordOutcome(id, input, vector)
        else -> throw ConformanceFailure("vector $id has unknown discovery-id kind")
    }
}

private fun discoveryIdComputeIdOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val fingerprint = hexToBytes(input.getValue("macSpkiFingerprintHex").jsonPrimitive.content)
    val unixSecondsUtc = input.getValue("unixSecondsUtc").jsonPrimitive.long
    val expected = vector.getValue("expected").jsonObject
    val expectedDayIndex = expected.getValue("dayIndex").jsonPrimitive.long
    val expectedIdHex = expected.getValue("idHex").jsonPrimitive.content

    val dayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc)
    val idHex = DiscoveryRotatingId.computeHex(fingerprint, dayIndex)

    val passed = dayIndex == expectedDayIndex && idHex == expectedIdHex
    return VectorOutcome(
        id,
        "discovery-id",
        if (passed) "pass" else "fail",
        "dayIndex=$expectedDayIndex idHex=$expectedIdHex",
        "dayIndex=$dayIndex idHex=$idHex",
    )
}

private fun discoveryIdRecognitionOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val pairedFingerprint = hexToBytes(input.getValue("pairedMacSpkiFingerprintHex").jsonPrimitive.content)
    val receiverUnixSecondsUtc = input.getValue("receiverUnixSecondsUtc").jsonPrimitive.long
    val advertisedFingerprint = hexToBytes(input.getValue("advertisedSpkiFingerprintHex").jsonPrimitive.content)
    val advertisedDayIndex = input.getValue("advertisedDayIndex").jsonPrimitive.long

    val receiverDayIndex = DiscoveryRotatingId.dayIndex(receiverUnixSecondsUtc)
    val candidateIdsHex = DiscoveryRotatingId.candidateHexIds(pairedFingerprint, receiverUnixSecondsUtc)
    val advertisedIdHex = DiscoveryRotatingId.computeHex(advertisedFingerprint, advertisedDayIndex)

    if ("expected" in vector) {
        return discoveryIdRecognitionExpectedOutcome(
            id,
            receiverDayIndex,
            candidateIdsHex,
            advertisedIdHex,
            vector.getValue("expected").jsonObject,
        )
    }

    val expectedError = vector.getValue("expectedError").jsonPrimitive.content
    val actualError =
        try {
            DiscoveryRotatingId.recognize(advertisedIdHex, candidateIdsHex)
            "no error thrown"
        } catch (_: DiscoveryRotatingId.RecognitionException.NotRecognized) {
            "notRecognized"
        }
    val passed = actualError == expectedError
    return VectorOutcome(id, "discovery-id", if (passed) "pass" else "fail", expectedError, actualError)
}

/** [receiverDayIndex]/[candidateIdsHex]/[advertisedIdHex]/[expected] bundled so this stays under
 * detekt's six-parameter limit. */
private fun discoveryIdRecognitionExpectedOutcome(
    id: String,
    receiverDayIndex: Long,
    candidateIdsHex: List<String>,
    advertisedIdHex: String,
    expected: JsonObject,
): VectorOutcome {
    val expectedDayIndex = expected.getValue("receiverDayIndex").jsonPrimitive.long
    val expectedCandidateIdsHex = expected.getValue("candidateIdsHex").jsonArray.map { it.jsonPrimitive.content }
    val expectedAdvertisedIdHex = expected.getValue("advertisedIdHex").jsonPrimitive.content

    val recognized =
        try {
            DiscoveryRotatingId.recognize(advertisedIdHex, candidateIdsHex)
            true
        } catch (_: DiscoveryRotatingId.RecognitionException.NotRecognized) {
            false
        }

    val passed =
        receiverDayIndex == expectedDayIndex &&
            candidateIdsHex == expectedCandidateIdsHex &&
            advertisedIdHex == expectedAdvertisedIdHex &&
            recognized

    val expectedDescription =
        "receiverDayIndex=$expectedDayIndex candidateIdsHex=$expectedCandidateIdsHex " +
            "advertisedIdHex=$expectedAdvertisedIdHex"
    val actualDescription =
        "receiverDayIndex=$receiverDayIndex candidateIdsHex=$candidateIdsHex advertisedIdHex=$advertisedIdHex"
    return VectorOutcome(id, "discovery-id", if (passed) "pass" else "fail", expectedDescription, actualDescription)
}

private fun discoveryIdTxtRecordOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val fields = mutableMapOf<String, String>()
    input["v"]?.jsonPrimitive?.content?.let { fields["v"] = it }
    input["idHex"]?.jsonPrimitive?.content?.let { fields["id"] = it }
    input["extraKeys"]?.jsonObject?.forEach { (key, value) -> fields[key] = value.jsonPrimitive.content }

    val expectedError = vector.getValue("expectedError").jsonPrimitive.content
    val actualError =
        try {
            val parsed = DiscoveryTxtRecord.parse(fields)
            input["candidateIdHex"]?.jsonPrimitive?.content?.let { candidateIdHex ->
                DiscoveryRotatingId.recognize(parsed.idHex, listOf(candidateIdHex))
            }
            "no error thrown"
        } catch (_: DiscoveryTxtRecord.ValidationError.MalformedTxtRecord) {
            "malformedTxtRecord"
        } catch (_: DiscoveryTxtRecord.ValidationError.UnsupportedVersion) {
            "unsupportedVersion"
        } catch (_: DiscoveryRotatingId.RecognitionException.NotRecognized) {
            "notRecognized"
        }

    val passed = actualError == expectedError
    return VectorOutcome(id, "discovery-id", if (passed) "pass" else "fail", expectedError, actualError)
}
