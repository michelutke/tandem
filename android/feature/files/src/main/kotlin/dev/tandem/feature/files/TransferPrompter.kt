package dev.tandem.feature.files

/** Shows and withdraws the accept/decline prompt for an incoming file offer (E40-07). */
interface TransferPrompter {
    /** [displayName] is already sanitized (E14-21). */
    fun post(
        offerId: String,
        displayName: String,
        sizeBytes: Long,
    )

    fun cancel(offerId: String)
}
