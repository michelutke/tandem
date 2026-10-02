package dev.tandem.core.pairing.conformance

import com.google.protobuf.InvalidProtocolBufferException
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.InputEvent
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E62-01: input-encoding conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerMedia.kt (mirrors the macOS codec's own
// ConformanceRunner+Input.swift split).

private const val CATEGORY = "input-encoding"
private const val SESSION_ID_LENGTH = 16
private const val MAX_TEXT_CHARACTERS = 4096
private const val MAX_SWIPE_DURATION_MS = 5000
private const val MAX_DELETE_BACKWARD = 64

private class Window(
    val width: Long,
    val height: Long,
) {
    fun contains(
        x: Int,
        y: Int,
    ): Boolean = x.toUInt().toLong() < width && y.toUInt().toLong() < height
}

/** `input-encoding` category (E62-01): decodes the serialized `InputEvent` each vector carries
 * (`input.messageHex`), applies the SPEC.md #input-events validation rules against the vector's active
 * session and window, and compares the result with `expectedError` or `expected.summary`; see
 * protocol/vectors/README.md. */
internal fun inputEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val bytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    return try {
        val decoded = InputEvent.parseFrom(bytes)
        val activeSession = hexToBytes(input.getValue("activeSessionIdHex").jsonPrimitive.content)
        val window =
            Window(
                input
                    .getValue("windowWidth")
                    .jsonPrimitive.content
                    .toLong(),
                input
                    .getValue("windowHeight")
                    .jsonPrimitive.content
                    .toLong(),
            )
        val verdict = inputVerdict(decoded, activeSession, window)
        if ("expectedError" in vector) {
            val expectedError = vector.getValue("expectedError").jsonPrimitive.content
            VectorOutcome(id, CATEGORY, if (verdict == expectedError) "pass" else "fail", expectedError, verdict)
        } else {
            positiveInputOutcome(id, vector, decoded, bytes, verdict)
        }
    } catch (e: InvalidProtocolBufferException) {
        VectorOutcome(id, CATEGORY, "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun positiveInputOutcome(
    id: String,
    vector: JsonObject,
    decoded: InputEvent,
    bytes: ByteArray,
    verdict: String,
): VectorOutcome {
    val expected = vector.getValue("expected").jsonObject
    val expectedSummary = expected.getValue("summary").jsonPrimitive.content
    val actualSummary = inputSummary(decoded)
    val passed =
        verdict == "accepted" &&
            actualSummary == expectedSummary &&
            decoded.toByteArray().contentEquals(bytes) &&
            sha256Hex(bytes) == expected.getValue("messageSha256").jsonPrimitive.content
    return VectorOutcome(id, CATEGORY, if (passed) "pass" else "fail", expectedSummary, actualSummary)
}

private fun inputVerdict(
    event: InputEvent,
    activeSession: ByteArray,
    window: Window,
): String =
    when {
        event.sessionId.size() != SESSION_ID_LENGTH -> "missingSessionReference"
        !event.sessionId.toByteArray().contentEquals(activeSession) -> "sessionMismatch"
        else -> eventVerdict(event, window)
    }

private fun eventVerdict(
    event: InputEvent,
    window: Window,
): String =
    when (event.eventCase) {
        InputEvent.EventCase.TAP -> {
            if (window.contains(event.tap.x, event.tap.y)) "accepted" else "coordinatesOutOfRange"
        }

        InputEvent.EventCase.SWIPE -> {
            swipeVerdict(event, window)
        }

        InputEvent.EventCase.SCROLL -> {
            if (window.contains(event.scroll.x, event.scroll.y)) "accepted" else "coordinatesOutOfRange"
        }

        InputEvent.EventCase.GLOBAL_ACTION -> {
            if (event.globalAction.action in KNOWN_ACTIONS) "accepted" else "unknownGlobalAction"
        }

        InputEvent.EventCase.SET_TEXT -> {
            textVerdict(event.setText.text)
        }

        InputEvent.EventCase.TEXT_EDIT -> {
            textEditVerdict(event)
        }

        InputEvent.EventCase.EVENT_NOT_SET -> {
            "unknownPayloadType"
        }
    }

private val KNOWN_ACTIONS =
    setOf(
        GlobalActionKind.GLOBAL_ACTION_KIND_BACK,
        GlobalActionKind.GLOBAL_ACTION_KIND_HOME,
        GlobalActionKind.GLOBAL_ACTION_KIND_RECENTS,
        GlobalActionKind.GLOBAL_ACTION_KIND_NOTIFICATIONS,
    )

private fun swipeVerdict(
    event: InputEvent,
    window: Window,
): String {
    val swipe = event.swipe
    return when {
        !window.contains(swipe.x1, swipe.y1) || !window.contains(swipe.x2, swipe.y2) -> "coordinatesOutOfRange"
        swipe.durationMs.toUInt().toLong() !in 1..MAX_SWIPE_DURATION_MS -> "durationOutOfRange"
        else -> "accepted"
    }
}

private fun textVerdict(text: String): String =
    if (text.codePointCount(0, text.length) <= MAX_TEXT_CHARACTERS) "accepted" else "textTooLong"

private fun textEditVerdict(event: InputEvent): String =
    when (event.textEdit.editCase) {
        dev.tandem.protocol.v1.TextEdit.EditCase.INSERT -> {
            textVerdict(event.textEdit.insert)
        }

        dev.tandem.protocol.v1.TextEdit.EditCase.DELETE_BACKWARD -> {
            if (event.textEdit.deleteBackward in 1..MAX_DELETE_BACKWARD) "accepted" else "deleteCountOutOfRange"
        }

        else -> {
            "accepted"
        }
    }

private fun inputSummary(event: InputEvent): String =
    when (event.eventCase) {
        InputEvent.EventCase.TAP -> {
            "variant=tap|x=${event.tap.x}|y=${event.tap.y}"
        }

        InputEvent.EventCase.SWIPE -> {
            event.swipe.let {
                "variant=swipe|x1=${it.x1}|y1=${it.y1}|x2=${it.x2}|y2=${it.y2}|durationMs=${it.durationMs}"
            }
        }

        InputEvent.EventCase.SCROLL -> {
            event.scroll.let { "variant=scroll|x=${it.x}|y=${it.y}|dx=${it.dx}|dy=${it.dy}" }
        }

        InputEvent.EventCase.GLOBAL_ACTION -> {
            "variant=globalAction|action=${event.globalAction.actionValue}"
        }

        InputEvent.EventCase.SET_TEXT -> {
            "variant=setText|text=${event.setText.text}"
        }

        InputEvent.EventCase.TEXT_EDIT -> {
            textEditSummary(event)
        }

        InputEvent.EventCase.EVENT_NOT_SET -> {
            "variant=unset"
        }
    }

private fun textEditSummary(event: InputEvent): String =
    when (event.textEdit.editCase) {
        dev.tandem.protocol.v1.TextEdit.EditCase.INSERT -> {
            "variant=textEdit|insert=${event.textEdit.insert}"
        }

        dev.tandem.protocol.v1.TextEdit.EditCase.DELETE_BACKWARD -> {
            "variant=textEdit|deleteBackward=${event.textEdit.deleteBackward}"
        }

        dev.tandem.protocol.v1.TextEdit.EditCase.IME_ENTER -> {
            "variant=textEdit|imeEnter"
        }

        dev.tandem.protocol.v1.TextEdit.EditCase.EDIT_NOT_SET -> {
            "variant=textEdit|unset"
        }
    }
