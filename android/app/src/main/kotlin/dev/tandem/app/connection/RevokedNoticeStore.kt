package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.io.IOException

/**
 * Persistent "[macName] removed this phone" notice (ui-spec §8, revoked by peer). Trust is deleted
 * when an authenticated Revoke arrives, so the Mac's name is kept in a marker file that outlives the
 * process and the trust record; it is cleared by a successful new pairing or by the user's dismissal.
 */
class RevokedNoticeStore(
    private val file: File,
) {
    private val state = MutableStateFlow(read())

    val macName: StateFlow<String?> = state.asStateFlow()

    @Synchronized
    fun mark(name: String) {
        try {
            file.parentFile?.mkdirs()
            file.writeText(name)
        } catch (_: IOException) {
            // The in-memory notice below still shows for this process.
        } finally {
            state.value = name
        }
    }

    @Synchronized
    fun clear() {
        file.delete()
        state.value = null
    }

    private fun read(): String? =
        try {
            if (file.exists()) file.readText() else null
        } catch (_: IOException) {
            null
        }
}

/**
 * [TrustRemover] for the authenticated Revoke path only: resolves the Mac's name, removes trust
 * through [delegate], then records the [notice]. A failed removal leaves no notice.
 */
class NoticingTrustRemover(
    private val macName: suspend (SpkiFingerprint) -> String?,
    private val notice: RevokedNoticeStore,
    private val delegate: TrustRemover,
) : TrustRemover {
    override suspend fun remove(fingerprint: SpkiFingerprint) {
        val name = lookUpName(fingerprint)
        delegate.remove(fingerprint)
        notice.mark(name)
    }

    @Suppress("TooGenericExceptionCaught")
    private suspend fun lookUpName(fingerprint: SpkiFingerprint): String =
        try {
            macName(fingerprint).orEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            ""
        }
}
