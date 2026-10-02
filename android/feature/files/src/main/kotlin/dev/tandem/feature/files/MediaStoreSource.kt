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

/** Keyset seam over MediaStore: rows ordered `DATE_TAKEN DESC, _ID DESC`, strictly after [after]. */
fun interface MediaStoreSource {
    fun query(
        after: MediaKey?,
        limit: Int,
    ): List<MediaRow>
}
