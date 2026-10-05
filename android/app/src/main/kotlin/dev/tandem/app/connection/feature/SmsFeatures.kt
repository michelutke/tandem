package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.feature.messaging.SendResultBus
import dev.tandem.feature.messaging.SendSmsHandler
import dev.tandem.feature.messaging.SendSmsPermission
import dev.tandem.feature.messaging.SimListPublisher
import dev.tandem.feature.messaging.SmsIncrementalSync
import dev.tandem.feature.messaging.SmsSender
import dev.tandem.feature.messaging.SmsSource
import dev.tandem.feature.messaging.SmsSyncSession
import dev.tandem.feature.messaging.SubscriptionSource
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * The SMS channel consumers (F-8.1, F-8.2), one [SessionFeature] each so a failing one (e.g. a
 * revoked SMS permission) never detaches the others. Their `log` seams stay at the no-op default
 * (invariant 7).
 */
@Suppress("LongParameterList") // one seam per SMS collaborator
class SmsFeatures(
    private val source: SmsSource,
    private val sender: SmsSender,
    private val sendPermission: SendSmsPermission,
    private val subscriptions: SubscriptionSource,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val ioDispatcher: CoroutineDispatcher,
) {
    fun all(): List<SessionFeature> = listOf(sync(), incrementalSync(), send(), simList())

    private fun sync() = SessionFeature { session, _, _ -> SmsSyncSession(source, session, ioDispatcher).run() }

    private fun incrementalSync() =
        SessionFeature { session, _, _ ->
            SmsIncrementalSync(source, session, ioDispatcher).run {
                withContext(ioDispatcher) { source.maxId() }
            }
        }

    private fun send() =
        SessionFeature { session, _, _ ->
            SendSmsHandler(
                sender,
                source,
                session,
                sendPermission,
                subscriptions,
                SendResultBus.results,
                elapsedRealtimeSource,
                ioDispatcher,
            ).run()
        }

    private fun simList() =
        SessionFeature { session, _, _ -> SimListPublisher(subscriptions, session, ioDispatcher).run() }
}
