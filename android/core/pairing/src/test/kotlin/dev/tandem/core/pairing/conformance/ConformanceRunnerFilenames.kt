package dev.tandem.core.pairing.conformance

import dev.tandem.core.protocol.FilenameSanitizer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private const val INVALID_NAME_ERROR = "invalidName"

/** `filenames` category (E40-02): runs the production FilenameSanitizer (E40-16)
 * over each vector's raw name. */
internal fun filenamesOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val name = String(hexToBytes(input.getValue("rawUtf8Hex").jsonPrimitive.content), Charsets.UTF_8)
    val transferId = input.getValue("transferId").jsonPrimitive.content
    val expected =
        vector["expectedError"]?.jsonPrimitive?.content
            ?: vector
                .getValue("expected")
                .jsonObject
                .getValue("filename")
                .jsonPrimitive.content
    val actual = FilenameSanitizer.sanitize(name, transferId) ?: INVALID_NAME_ERROR
    return VectorOutcome(id, "filenames", if (actual == expected) "pass" else "fail", expected, actual)
}
