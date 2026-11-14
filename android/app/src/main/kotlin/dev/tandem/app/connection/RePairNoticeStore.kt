package dev.tandem.app.connection

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.io.IOException

/**
 * Persistent "this phone's identity was reset, so its paired Mac no longer recognizes it" notice
 * (SPEC.md invariants 3 and 5). The marker file outlives the process: it is set when
 * [dev.tandem.core.crypto.IdentityBootstrapper] replaces an identity a peer was paired against, and
 * cleared only once a new pairing commits trust.
 */
class RePairNoticeStore(
    private val file: File,
) {
    private val state = MutableStateFlow(file.exists())

    val required: StateFlow<Boolean> = state.asStateFlow()

    @Synchronized
    fun require() {
        try {
            file.parentFile?.mkdirs()
            file.createNewFile()
        } catch (_: IOException) {
            return
        } finally {
            state.value = true
        }
    }

    @Synchronized
    fun clear() {
        file.delete()
        state.value = false
    }
}
