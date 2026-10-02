package dev.tandem.feature.files

import dev.tandem.core.protocol.DisplayStringKind
import dev.tandem.core.protocol.DisplayStringSanitizer
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileReject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

/** Receiver-side auto-accept setting (D-44): off by default; applies only to offers <= [autoAcceptMaxBytes]. */
data class AcceptSettings(
    val autoAccept: Boolean = false,
    val autoAcceptMaxBytes: Long = DEFAULT_AUTO_ACCEPT_MAX_BYTES,
) {
    companion object {
        const val DEFAULT_AUTO_ACCEPT_MAX_BYTES: Long = 1L shl 30
    }
}

/**
 * Receiver half of the FILES offer handshake (E40-07; SPEC.md #files-channel "Cycle 4 caps" and
 * "Unanswered-offer timeout"). Per [FileOffer], in order: over 64 GiB -> `TOO_LARGE`; 4 pending
 * offers or [activeTransfers] >= 2 -> `BUSY`; free space below size + 64 MiB ->
 * `INSUFFICIENT_SPACE`; auto-accept on and size within its cap -> `FileAccept`; otherwise
 * [prompter] shows a prompt, answered by [accept]/[decline] or rejected `TIMEOUT` after 300 s.
 * Rejections never prompt.
 *
 * [dispatcher] MUST be single-threaded: all state is confined to it ([accept]/[decline] hop onto
 * it). Invariant 7: never logs names or sizes.
 */
class AcceptFlow(
    private val session: TandemSession,
    private val freeSpace: FreeSpaceProvider,
    private val prompter: TransferPrompter,
    private val settings: () -> AcceptSettings,
    private val activeTransfers: () -> Int,
    dispatcher: CoroutineDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    // Offer id -> its 300 s timeout job. Only touched on the scope's dispatcher.
    private val pending = mutableMapOf<String, Job>()

    init {
        session
            .receive(Channel.CHANNEL_FILES)
            .filter { it.hasFileOffer() }
            .onEach { onOffer(it.fileOffer) }
            .launchIn(scope)
    }

    fun accept(offerId: String) {
        scope.launch {
            if (resolvePending(offerId)) {
                session.send(Channel.CHANNEL_FILES) { fileAccept = fileAccept { id = offerId } }
            }
        }
    }

    fun decline(offerId: String) {
        scope.launch {
            if (resolvePending(offerId)) reject(offerId, TransferReason.TRANSFER_REASON_DECLINED)
        }
    }

    fun close() {
        scope.cancel()
    }

    private suspend fun onOffer(offer: FileOffer) {
        val rejection = rejectionFor(offer)
        when {
            rejection != null -> reject(offer.id, rejection)
            shouldAutoAccept(offer) -> session.send(Channel.CHANNEL_FILES) { fileAccept = fileAccept { id = offer.id } }
            else -> promptFor(offer)
        }
    }

    private fun rejectionFor(offer: FileOffer): TransferReason? {
        val busy = pending.size >= MAX_PENDING_OFFERS || activeTransfers() >= MAX_ACTIVE_TRANSFERS
        return when {
            offer.size > MAX_OFFER_BYTES -> {
                TransferReason.TRANSFER_REASON_TOO_LARGE
            }

            busy -> {
                TransferReason.TRANSFER_REASON_BUSY
            }

            freeSpace.freeBytes() < offer.size + SPACE_RESERVE_BYTES -> {
                TransferReason.TRANSFER_REASON_INSUFFICIENT_SPACE
            }

            else -> {
                null
            }
        }
    }

    private fun shouldAutoAccept(offer: FileOffer): Boolean {
        val current = settings()
        return current.autoAccept && offer.size <= current.autoAcceptMaxBytes
    }

    private fun promptFor(offer: FileOffer) {
        val name = DisplayStringSanitizer.sanitize(offer.name.toByteArray(Charsets.UTF_8), DisplayStringKind.NAME)
        prompter.post(offer.id, name, offer.size)
        pending[offer.id] =
            scope.launch {
                delay(OFFER_TIMEOUT)
                pending.remove(offer.id)
                prompter.cancel(offer.id)
                reject(offer.id, TransferReason.TRANSFER_REASON_TIMEOUT)
            }
    }

    /** Removes [offerId] from pending, stops its timeout and withdraws its prompt; false if not pending. */
    private fun resolvePending(offerId: String): Boolean {
        val timeout = pending.remove(offerId) ?: return false
        timeout.cancel()
        prompter.cancel(offerId)
        return true
    }

    private suspend fun reject(
        offerId: String,
        why: TransferReason,
    ) {
        session.send(Channel.CHANNEL_FILES) {
            fileReject =
                fileReject {
                    id = offerId
                    reason = why
                }
        }
    }

    private companion object {
        const val MAX_OFFER_BYTES = 1L shl 36
        const val SPACE_RESERVE_BYTES = 64L * 1024 * 1024
        const val MAX_PENDING_OFFERS = 4
        const val MAX_ACTIVE_TRANSFERS = 2
        val OFFER_TIMEOUT = 300.seconds
    }
}
