package dev.tandem.core.pairing.rotation

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Clock
import java.time.Duration
import java.time.Instant

/** Persists the instant the next scheduled rotation is due (E70-07). */
interface NextRotationDueStore {
    fun get(): Instant?

    fun set(due: Instant)
}

/**
 * [NextRotationDueStore] backed by [file]: epoch milliseconds, replaced atomically so a crash leaves
 * either the old or the new instant. A missing or unparsable file reads as no due instant.
 */
class FileNextRotationDueStore(
    private val file: File,
) : NextRotationDueStore {
    override fun get(): Instant? =
        file
            .takeIf { it.isFile }
            ?.readText()
            ?.trim()
            ?.toLongOrNull()
            ?.let(Instant::ofEpochMilli)

    override fun set(due: Instant) {
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(due.toEpochMilli().toString())
        Files.move(
            temporary.toPath(),
            file.toPath(),
            StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING,
        )
    }
}

/**
 * Periodic key rotation (E70-07; SPEC.md #key-rotation, Timeouts and scheduling). [run] suspends
 * for the life of its scope and counts down only while [authenticated] is true: a due instant that
 * passes offline is acted on when the next authenticated session starts. The due instant lives in
 * [store] (first run: now + [interval]) and moves to now + [interval] after a [RotationOutcome.Committed];
 * any other outcome leaves it due, to be retried on the next authenticated session.
 * [rotate] holds the rotation lock itself. Never logs keys or fingerprints.
 */
class RotationScheduler(
    private val clock: Clock,
    private val interval: Duration,
    private val store: NextRotationDueStore,
    private val authenticated: Flow<Boolean>,
    private val rotate: suspend () -> RotationOutcome,
) {
    suspend fun run() {
        authenticated.collectLatest { isAuthenticated ->
            if (isAuthenticated) rotateWhenDue()
        }
    }

    private suspend fun rotateWhenDue() {
        while (true) {
            val due = store.get() ?: clock.instant().plus(interval).also(store::set)
            val wait = Duration.between(clock.instant(), due)
            if (!wait.isNegative && !wait.isZero) delay(wait.toMillis())
            if (rotate() != RotationOutcome.Committed) return
            store.set(clock.instant().plus(interval))
        }
    }
}
