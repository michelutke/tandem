package dev.tandem.core.pairing.conformance

import com.google.protobuf.ByteString
import dev.tandem.core.protocol.ContactThumbnailValidator
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactsSyncRequest
import dev.tandem.protocol.v1.ContactsSyncResponse
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E51-01: contacts-encoding conformance vector handlers, split out of ConformanceRunner.kt purely
// to keep that object's LargeClass detekt budget (mirrors ConformanceRunnerFiles.kt / the macOS
// codec's own ConformanceRunner+Contacts.swift split).

/** `contacts-encoding` category (E51-01): decodes the raw message bytes each vector describes
 * (`input.messageHex`, or `input.thumbnailRecipe` for the oversized-thumbnail vector -- see
 * protocol/vectors/README.md) with the real generated CONTACTS message types, selected by
 * `input.kind`. `contact` vectors are additionally validated against the CONTACTS channel's
 * 32,768-byte `photo_thumbnail` cap via the real [ContactThumbnailValidator], not just asserted at
 * the vector level. */
internal fun contactsEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val kind = input.getValue("kind").jsonPrimitive.content
    return when (kind) {
        "contact" -> contactOutcome(id, input, vector)
        "contactsSyncRequest" -> contactsSyncRequestOutcome(id, input, vector)
        "contactsSyncResponse" -> contactsSyncResponseOutcome(id, input, vector)
        else -> error("unsupported contacts-encoding kind: $kind")
    }
}

private fun contactOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = contactBytes(input)
    val decoded =
        try {
            Contact.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "contacts-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val accepted = ContactThumbnailValidator.isValid(decoded.photoThumbnail.toByteArray())

    return when {
        "expected" in vector && !accepted -> {
            VectorOutcome(id, "contacts-encoding", "fail", "accepted", "rejected: contactPhotoThumbnailTooLarge")
        }

        "expected" in vector -> {
            contactValidOutcome(id, vector.getValue("expected").jsonObject, decoded)
        }

        else -> {
            val expectedError = vector.getValue("expectedError").jsonPrimitive.content
            val actual = if (accepted) "accepted" else "contactPhotoThumbnailTooLarge"
            val outcome = if (actual == expectedError) "pass" else "fail"
            VectorOutcome(id, "contacts-encoding", outcome, expectedError, actual)
        }
    }
}

private fun contactValidOutcome(
    id: String,
    expected: JsonObject,
    decoded: Contact,
): VectorOutcome {
    val expectedContactId = expected.getValue("contactId").jsonPrimitive.content
    val expectedDisplayName = expected.getValue("displayName").jsonPrimitive.content
    val expectedPhotoThumbnailHex = expected.getValue("photoThumbnailHex").jsonPrimitive.content
    val expectedUpdatedAtMs =
        expected
            .getValue("updatedAtMs")
            .jsonPrimitive.content
            .toLong()
    val expectedPhoneNumbers = expected.getValue("phoneNumbers").jsonArray
    val expectedEmails = expected.getValue("emails").jsonArray

    val phoneNumbersMatch =
        decoded.phoneNumbersList.size == expectedPhoneNumbers.size &&
            decoded.phoneNumbersList.zip(expectedPhoneNumbers).all { (actualPhone, expectedPhoneElement) ->
                val expectedPhone = expectedPhoneElement.jsonObject
                actualPhone.number == expectedPhone.getValue("number").jsonPrimitive.content &&
                    actualPhone.normalizedE164 == expectedPhone.getValue("normalizedE164").jsonPrimitive.content &&
                    actualPhone.type.name == expectedPhone.getValue("type").jsonPrimitive.content
            }
    val emailsMatch =
        decoded.emailsList.size == expectedEmails.size &&
            decoded.emailsList.zip(expectedEmails).all { (actualEmail, expectedEmailElement) ->
                val expectedEmail = expectedEmailElement.jsonObject
                actualEmail.address == expectedEmail.getValue("address").jsonPrimitive.content &&
                    actualEmail.type.name == expectedEmail.getValue("type").jsonPrimitive.content
            }

    val passed =
        decoded.contactId == expectedContactId &&
            decoded.displayName == expectedDisplayName &&
            decoded.photoThumbnail.toByteArray().toHex() == expectedPhotoThumbnailHex &&
            decoded.updatedAtMs == expectedUpdatedAtMs &&
            phoneNumbersMatch &&
            emailsMatch
    val expectedDescription = "contactId=$expectedContactId displayName=$expectedDisplayName"
    val actualDescription = "contactId=${decoded.contactId} displayName=${decoded.displayName}"
    return VectorOutcome(
        id,
        "contacts-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}

private fun contactBytes(input: JsonObject): ByteArray {
    input["messageHex"]?.jsonPrimitive?.content?.let { return hexToBytes(it) }

    val recipe = input.getValue("thumbnailRecipe").jsonObject
    val fillByte = hexToBytes(recipe.getValue("fillByte").jsonPrimitive.content).first()
    val fillLength =
        recipe
            .getValue("fillLength")
            .jsonPrimitive
            .content
            .toInt()
    val thumbnail = ByteArray(fillLength) { fillByte }
    return Contact
        .newBuilder()
        .setPhotoThumbnail(ByteString.copyFrom(thumbnail))
        .build()
        .toByteArray()
}

private fun contactsSyncRequestOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            ContactsSyncRequest.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "contacts-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expectedSinceUpdatedAtMs =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("sinceUpdatedAtMs")
            .jsonPrimitive.content
            .toLong()
    val passed = decoded.sinceUpdatedAtMs == expectedSinceUpdatedAtMs
    return VectorOutcome(
        id,
        "contacts-encoding",
        if (passed) "pass" else "fail",
        "sinceUpdatedAtMs=$expectedSinceUpdatedAtMs",
        "sinceUpdatedAtMs=${decoded.sinceUpdatedAtMs}",
    )
}

private fun contactsSyncResponseOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            ContactsSyncResponse.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "contacts-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedStatus = expected.getValue("status").jsonPrimitive.content
    val expectedContactCount =
        expected
            .getValue("contactCount")
            .jsonPrimitive.content
            .toInt()
    val expectedDeletedIds =
        expected
            .getValue("deletedContactIds")
            .jsonArray
            .map { it.jsonPrimitive.content }
    val expectedWatermarkMs =
        expected
            .getValue("watermarkMs")
            .jsonPrimitive.content
            .toLong()
    val expectedComplete =
        expected
            .getValue("complete")
            .jsonPrimitive.content
            .toBoolean()

    val passed =
        decoded.status.name == expectedStatus &&
            decoded.contactsList.size == expectedContactCount &&
            decoded.deletedContactIdsList == expectedDeletedIds &&
            decoded.watermarkMs == expectedWatermarkMs &&
            decoded.complete == expectedComplete
    val expectedDescription = "status=$expectedStatus deletedContactIds=$expectedDeletedIds"
    val actualDescription = "status=${decoded.status.name} deletedContactIds=${decoded.deletedContactIdsList}"
    return VectorOutcome(
        id,
        "contacts-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}
