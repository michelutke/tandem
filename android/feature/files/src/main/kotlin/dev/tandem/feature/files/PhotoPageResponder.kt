package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoPage
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
        return pager.page(request, access)
    }
}
