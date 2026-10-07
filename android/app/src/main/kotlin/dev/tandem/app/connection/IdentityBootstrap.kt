package dev.tandem.app.connection

import dev.tandem.core.pairing.IdentityUnavailableException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Creates (or reuses) the phone's identity key once before any TLS use (invariants 1, 5). Called at
 * app start and awaited by every dial path; a failure throws [IdentityUnavailableException] and is
 * retried on the next [ensure].
 */
class IdentityBootstrap(
    private val bootstrap: () -> Unit,
    private val dispatcher: CoroutineDispatcher,
) {
    private val mutex = Mutex()

    @Volatile
    private var ready = false

    @Suppress("TooGenericExceptionCaught") // key-store failures span provider-specific unchecked types
    suspend fun ensure() {
        if (ready) return
        mutex.withLock {
            if (ready) return
            try {
                withContext(dispatcher) { bootstrap() }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (failure: Exception) {
                throw IdentityUnavailableException(failure)
            }
            ready = true
        }
    }
}
