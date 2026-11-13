package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoErrorKind
import dev.tandem.protocol.v1.PhotoErrorReason
import dev.tandem.protocol.v1.PhotoPage
import dev.tandem.protocol.v1.photoError
import dev.tandem.protocol.v1.photoPageResult

/**
 * Answers a `PhotoPage` request: a `PhotoPageResult` on success, a `PhotoError` on failure. With NONE
 * access it returns zero items without touching [pager].
 */
class PhotoPageResponder(
    private val permissionChecker: MediaPermissionChecker,
    private val pager: PhotoPager,
) {
    fun respond(request: PhotoPage): PhotoPageOutcome {
        val access = permissionChecker.access()
        if (access == PhotoAccess.PHOTO_ACCESS_NONE) {
            return PhotoPageOutcome.Page(photoPageResult { this.access = access })
        }
        return try {
            pager.page(request, access)
        } catch (_: RuntimeException) {
            PhotoPageOutcome.Failure(
                photoError {
                    kind = PhotoErrorKind.PHOTO_ERROR_KIND_PAGE
                    reason = PhotoErrorReason.PHOTO_ERROR_REASON_NOT_FOUND
                },
            )
        }
    }
}
