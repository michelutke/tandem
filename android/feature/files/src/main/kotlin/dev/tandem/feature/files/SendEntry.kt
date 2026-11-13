package dev.tandem.feature.files

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.net.toUri
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** Starts one FileOffer for [request]; the seam stands in for the (not yet wired) live [FileSender]. */
fun interface TransferStarter {
    fun start(request: SendRequest)
}

/**
 * Gate and fan-out for files handed to Tandem by another app's share sheet or the SAF picker (E40-11).
 * Only `content://` URIs are accepted, none may belong to this app's own package (confused deputy),
 * and one share is capped at [MAX_STREAMS]; any violation rejects the whole batch so nothing is sent.
 * With [staging], each accepted stream is copied into the app cache and the request reads that copy
 * (the share-sheet grant does not outlive the activity). Invariant 7: never logs names or URIs.
 */
class SendEntry(
    private val ownPackage: String,
    private val contentResolver: ContentResolver,
    private val starter: TransferStarter,
    private val staging: ShareStaging? = null,
    private val onStagingFailed: () -> Unit = {},
) {
    /**
     * Queries the providers (and, with [staging], copies every stream), so call it off the main thread.
     * Any streams that cannot be staged within [ShareStaging.MAX_STAGED_BYTES] reject the whole batch.
     */
    fun offer(uris: List<Uri>): Boolean {
        val requests = if (isAcceptableBatch(uris)) stagedRequests(uris) else null
        requests?.forEach(starter::start)
        return requests != null
    }

    private fun isAcceptableBatch(uris: List<Uri>): Boolean =
        uris.isNotEmpty() && uris.size <= MAX_STREAMS && uris.all(::isAcceptable)

    private fun stagedRequests(uris: List<Uri>): List<SendRequest>? {
        val requests = uris.map(::request)
        return if (staging == null) requests else stage(staging, uris, requests)
    }

    private fun stage(
        staging: ShareStaging,
        uris: List<Uri>,
        requests: List<SendRequest>,
    ): List<SendRequest>? {
        val staged = mutableListOf<SendRequest>()
        var remaining = ShareStaging.MAX_STAGED_BYTES
        try {
            requests.forEachIndexed { index, request ->
                val file = staging.stage(contentResolver, uris[index], request.id, remaining)
                remaining -= file.length()
                staged += request.copy(uri = file.toUri().toString())
            }
        } catch (_: IOException) {
            staged.forEach(staging::delete)
            onStagingFailed()
            return null
        }
        return staged
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

        /** Where entry points run [offer]: provider queries and file copies stay off the main thread. */
        val BACKGROUND: Executor =
            Executors.newSingleThreadExecutor { task -> Thread(task, "send-entry").apply { isDaemon = true } }

        private const val FALLBACK_NAME = "file"
        private const val FALLBACK_MIME = "application/octet-stream"
    }
}
