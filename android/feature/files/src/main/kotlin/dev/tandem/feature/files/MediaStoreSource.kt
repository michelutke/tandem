package dev.tandem.feature.files

data class MediaRow(
    val id: Long,
    val dateTaken: Long,
    val width: Int,
    val height: Int,
)

data class MediaKey(
    val dateTaken: Long,
    val id: Long,
)

/** One MediaStore image as served to the Mac: [uri] opens through `SourceFileReader`. */
data class MediaItem(
    val uri: String,
    val displayName: String,
    val mime: String,
)

/**
 * Keyset seam over MediaStore: rows ordered `DATE_TAKEN DESC, _ID DESC`, strictly after [after].
 * [item] returns null for a missing id and throws [SecurityException] for an id outside the media grant.
 */
fun interface MediaStoreSource {
    fun query(
        after: MediaKey?,
        limit: Int,
    ): List<MediaRow>

    fun item(id: Long): MediaItem? = null
}
