package dev.tandem.feature.files

import dev.tandem.protocol.v1.PhotoAccess
import dev.tandem.protocol.v1.PhotoPage
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.photoPageResult

fun interface PhotoPageSource {
    fun query(
        request: PhotoPage,
        access: PhotoAccess,
    ): PhotoPageResult
}

/** Answers a `PhotoPage` request: with NONE access it returns zero items without touching [source]. */
class PhotoPageResponder(
    private val permissionChecker: MediaPermissionChecker,
    private val source: PhotoPageSource,
) {
    fun respond(request: PhotoPage): PhotoPageResult {
        val access = permissionChecker.access()
        if (access == PhotoAccess.PHOTO_ACCESS_NONE) {
            return photoPageResult { this.access = access }
        }
        return source.query(request, access)
    }
}
