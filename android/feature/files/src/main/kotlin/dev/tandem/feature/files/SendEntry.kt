package dev.tandem.feature.files

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.util.UUID

/** Starts one FileOffer for [request]; the seam stands in for the (not yet wired) live [FileSender]. */
fun interface TransferStarter {
    fun start(request: SendRequest)
}

/**
 * Gate and fan-out for files handed to Tandem by another app's share sheet or the SAF picker (E40-11).
 * Only `content://` URIs are accepted, none may belong to this app's own package (confused deputy),
 * and one share is capped at [MAX_STREAMS]; any violation rejects the whole batch so nothing is sent.
 * Invariant 7: never logs names or URIs.
 */
class SendEntry(
    private val ownPackage: String,
    private val contentResolver: ContentResolver,
    private val starter: TransferStarter,
) {
    fun offer(uris: List<Uri>): Boolean {
        if (uris.isEmpty() || uris.size > MAX_STREAMS || !uris.all(::isAcceptable)) return false
        uris.forEach { starter.start(request(it)) }
        return true
    }

    private fun isAcceptable(uri: Uri): Boolean {
        val host = uri.host?.lowercase()
        val own = ownPackage.lowercase()
        return uri.scheme == ContentResolver.SCHEME_CONTENT && host != null && host != own && !host.startsWith("$own.")
    }

    private fun request(uri: Uri): SendRequest =
        SendRequest(
            id = UUID.randomUUID().toString(),
            uri = uri.toString(),
            name = displayName(uri),
            mime = contentResolver.getType(uri) ?: FALLBACK_MIME,
        )

    private fun displayName(uri: Uri): String =
        contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            ?: FALLBACK_NAME

    companion object {
        const val MAX_STREAMS = 20
        private const val FALLBACK_NAME = "file"
        private const val FALLBACK_MIME = "application/octet-stream"
    }
}
