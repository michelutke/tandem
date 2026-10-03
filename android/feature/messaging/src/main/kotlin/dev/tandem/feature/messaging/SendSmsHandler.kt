package dev.tandem.feature.messaging

import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.SendSmsErrorCode
import dev.tandem.protocol.v1.SendSmsRequest
import dev.tandem.protocol.v1.SendSmsState
import dev.tandem.protocol.v1.sendSmsStatus
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * E50-04 phone side of the SMS send flow (PRD F-8.2, docs/protocol/SPEC.md #sms-channel "Send"):
 * validates each `SendSmsRequest`, sends it through [sender], and reports `SendSmsStatus` frames
 * that echo `clientMessageId`. Requests failing a check are answered `FAILED` without calling
 * [sender]. [log] receives result codes and client message ids only, never bodies or addresses
 * (invariant 7).
 */
@Suppress("LongParameterList") // independent injected seams: sender, source, session, permission, clock, dispatcher
class SendSmsHandler(
    private val sender: SmsSender,
    private val source: SmsSource,
    private val session: TandemSession,
    private val permission: SendSmsPermission,
    private val subscriptions: SubscriptionSource,
    private val results: SharedFlow<PartResult>,
    elapsed: ElapsedRealtimeSource,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    private val rateLimiter = SendRateLimiter(elapsed)

    /** Handles every `SendSmsRequest` on the SMS channel, each in its own coroutine. */
    suspend fun run() {
        coroutineScope {
            session
                .receive(Channel.CHANNEL_SMS)
                .filter { it.hasSendSmsRequest() }
                .collect { envelope -> launch { handle(envelope.sendSmsRequest) } }
        }
    }

    suspend fun handle(request: SendSmsRequest) {
        val destination = request.address.filterNot { it == ' ' || it == '-' }
        val choice =
            withContext(ioDispatcher) {
                SimChooser.choose(
                    request.subscriptionId,
                    subscriptions.activeSubscriptions(),
                    subscriptions.defaultSmsSubscriptionId(),
                )
            }
        val rejection = rejection(request, destination, choice)
        if (rejection != null) {
            log("sms send rejected: id=${request.clientMessageId} error=${rejection.name}")
            report(request.clientMessageId, SendSmsState.SEND_SMS_STATE_FAILED, rejection)
            return
        }
        val subscriptionId = (choice as SimChoice.Use).subscriptionId
        val parts = sender.divide(request.body)
        val baselineId = baselineId()
        val aggregator = SendStatusAggregator(parts.size)
        report(request.clientMessageId, SendSmsState.SEND_SMS_STATE_SENDING)
        results
            .onSubscription {
                withContext(ioDispatcher) {
                    sender.send(OutgoingSms(request.clientMessageId, destination, subscriptionId, parts))
                }
            }.filter { it.clientMessageId == request.clientMessageId }
            .transformWhile { part ->
                aggregator.accept(part).forEach { emit(it) }
                !aggregator.finished
            }.collect { update -> reportUpdate(request, destination, baselineId, update) }
    }

    private fun rejection(
        request: SendSmsRequest,
        destination: String,
        choice: SimChoice,
    ): SendSmsErrorCode? =
        when {
            !permission.isGranted() -> {
                SendSmsErrorCode.SEND_SMS_ERROR_CODE_PERMISSION_REQUIRED
            }

            !ADDRESS_PATTERN.matches(destination) -> {
                SendSmsErrorCode.SEND_SMS_ERROR_CODE_INVALID_ADDRESS
            }

            request.body.codePointCount(0, request.body.length) > MAX_BODY_CHARS -> {
                SendSmsErrorCode.SEND_SMS_ERROR_CODE_TOO_LONG
            }

            choice is SimChoice.Reject -> {
                choice.errorCode
            }

            !rateLimiter.tryAcquire() -> {
                SendSmsErrorCode.SEND_SMS_ERROR_CODE_RATE_LIMITED
            }

            else -> {
                null
            }
        }

    private suspend fun baselineId(): Long =
        try {
            withContext(ioDispatcher) { source.maxId() }
        } catch (_: SmsPermissionMissing) {
            0L
        }

    private suspend fun reportUpdate(
        request: SendSmsRequest,
        destination: String,
        baselineId: Long,
        update: SendUpdate,
    ) {
        when (update) {
            SendUpdate.Sent -> {
                report(
                    request.clientMessageId,
                    SendSmsState.SEND_SMS_STATE_SENT,
                    providerMessageId = providerMessageId(destination, baselineId),
                )
            }

            SendUpdate.Delivered -> {
                report(request.clientMessageId, SendSmsState.SEND_SMS_STATE_DELIVERED)
            }

            is SendUpdate.Failed -> {
                log("sms send failed: id=${request.clientMessageId} resultCode=${update.resultCode}")
                report(request.clientMessageId, SendSmsState.SEND_SMS_STATE_FAILED, update.errorCode)
            }
        }
    }

    private suspend fun providerMessageId(
        destination: String,
        baselineId: Long,
    ): Long {
        var waitedMs = 0L
        while (true) {
            val id =
                try {
                    withContext(ioDispatcher) { source.newestOutgoingId(destination, baselineId) }
                } catch (_: SmsPermissionMissing) {
                    return 0L
                }
            if (id != 0L || waitedMs >= PROVIDER_LOOKUP_TIMEOUT_MS) return id
            delay(PROVIDER_POLL_MS)
            waitedMs += PROVIDER_POLL_MS
        }
    }

    private suspend fun report(
        clientMessageId: String,
        state: SendSmsState,
        errorCode: SendSmsErrorCode = SendSmsErrorCode.SEND_SMS_ERROR_CODE_UNSPECIFIED,
        providerMessageId: Long = 0L,
    ) {
        session.send(Channel.CHANNEL_SMS) {
            sendSmsStatus =
                sendSmsStatus {
                    this.clientMessageId = clientMessageId
                    this.state = state
                    this.errorCode = errorCode
                    this.providerMessageId = providerMessageId
                }
        }
    }

    private companion object {
        const val MAX_BODY_CHARS = 1600
        const val PROVIDER_LOOKUP_TIMEOUT_MS = 5_000L
        const val PROVIDER_POLL_MS = 250L
        val ADDRESS_PATTERN = Regex("^\\+?[0-9]{3,20}$")
    }
}
