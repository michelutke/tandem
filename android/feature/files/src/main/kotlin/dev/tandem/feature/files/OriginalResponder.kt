package dev.tandem.feature.files

import dev.tandem.protocol.v1.OriginalRequest
import dev.tandem.protocol.v1.PhotoError
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.photoError
import kotlinx.coroutines.flow.StateFlow

sealed interface OriginalOutcome {
    data class Started(
        val state: StateFlow<SenderState>,
    ) : OriginalOutcome

    data class Failure(
        val error: PhotoError,
    ) : OriginalOutcome
}

/**
 * Answers an `OriginalRequest` by starting the standard [FileSender] transfer with
 * `FileOffer.id = transfer_id` (SPEC.md #files-channel "Photos"). An unknown id fails NOT_FOUND, an id
 * outside the current media grant fails ACCESS_DENIED; neither sends a `FileOffer`.
 */
class OriginalResponder(
    private val source: MediaStoreSource,
    private val sender: FileSender,
) {
    fun respond(request: OriginalRequest): OriginalOutcome =
        try {
            val item = request.id.toLongOrNull()?.let { source.item(it) }
            if (item == null) {
                failure(request.id, PhotoErrorReason.PHOTO_ERROR_REASON_NOT_FOUND)
            } else {
                OriginalOutcome.Started(
                    sender.send(SendRequest(request.transferId, item.uri, item.displayName, item.mime)),
                )
            }
        } catch (_: SecurityException) {
            failure(request.id, PhotoErrorReason.PHOTO_ERROR_REASON_ACCESS_DENIED)
        }

    private fun failure(
        id: String,
        reason: PhotoErrorReason,
    ): OriginalOutcome.Failure =
        OriginalOutcome.Failure(
            photoError {
                kind = PhotoErrorKind.PHOTO_ERROR_KIND_ORIGINAL
                ref = id.take(MAX_REF_LENGTH)
                this.reason = reason
            },
        )

    private companion object {
        const val MAX_REF_LENGTH = 64
    }
}
