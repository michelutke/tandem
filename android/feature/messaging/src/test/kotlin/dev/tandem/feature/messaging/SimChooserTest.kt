package dev.tandem.feature.messaging

import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.SendSmsErrorCode
import dev.tandem.protocol.v1.SendSmsRequest
import dev.tandem.protocol.v1.SendSmsState
import dev.tandem.protocol.v1.sendSmsRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** SIM chooser and SimList publisher tests (E50-05; `docs/planning/backlog/phase-5.yaml` E50-05's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class SimChooserTest {
    private val sim1 = SimInfo(subscriptionId = 1, displayName = "Carrier A", slotIndex = 0)
    private val sim2 = SimInfo(subscriptionId = 2, displayName = "Carrier B", slotIndex = 1)

    @Test
    fun simChooser_explicitSubscriptionIdOnDualSim_usesThatSubscriptionSender() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1, sim2), defaultSubscriptionId = 1)
            val sender = RecordingSmsSender()

            sendUntilDispatched(handler(this, subscriptions, sender), request(subscriptionId = 2))

            assertEquals(listOf(2), sender.sent.map { it.subscriptionId })
        }

    @Test
    fun simChooser_noSubscriptionIdOnSingleSim_usesDefaultSender() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1))
            val sender = RecordingSmsSender()

            sendUntilDispatched(handler(this, subscriptions, sender), request())

            assertEquals(listOf(0), sender.sent.map { it.subscriptionId })
        }

    @Test
    fun simChooser_noSubscriptionIdOnDualSimWithDefault_usesDefaultSubscription() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1, sim2), defaultSubscriptionId = 2)
            val sender = RecordingSmsSender()

            sendUntilDispatched(handler(this, subscriptions, sender), request())

            assertEquals(listOf(2), sender.sent.map { it.subscriptionId })
        }

    @Test
    fun simChooser_noSubscriptionIdOnDualSimNoDefault_failsSubscriptionRequired() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1, sim2))
            val sender = RecordingSmsSender()
            val session = FakeTandemSession()

            handler(this, subscriptions, sender, session).handle(request())

            assertTrue(sender.sent.isEmpty())
            assertEquals(
                listOf(
                    SendSmsState.SEND_SMS_STATE_FAILED to SendSmsErrorCode.SEND_SMS_ERROR_CODE_SUBSCRIPTION_REQUIRED,
                ),
                statuses(session),
            )
        }

    @Test
    fun simChooser_unknownSubscriptionId_failsInvalidSubscription() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1, sim2), defaultSubscriptionId = 1)
            val sender = RecordingSmsSender()
            val session = FakeTandemSession()

            handler(this, subscriptions, sender, session).handle(request(subscriptionId = 9))

            assertTrue(sender.sent.isEmpty())
            assertEquals(
                listOf(
                    SendSmsState.SEND_SMS_STATE_FAILED to SendSmsErrorCode.SEND_SMS_ERROR_CODE_INVALID_SUBSCRIPTION,
                ),
                statuses(session),
            )
        }

    @Test
    fun simChooser_noActiveSubscriptions_usesDefaultSender() =
        runTest {
            val sender = RecordingSmsSender()

            sendUntilDispatched(handler(this, FakeSubscriptionSource(), sender), request(subscriptionId = 2))

            assertEquals(listOf(0), sender.sent.map { it.subscriptionId })
        }

    @Test
    fun simListPublisher_subscriptionsChanged_sendsUpdatedSimList() =
        runTest {
            val subscriptions = FakeSubscriptionSource(listOf(sim1))
            val session = FakeTandemSession()
            val publisher = SimListPublisher(subscriptions, session, StandardTestDispatcher(testScheduler))
            val job = launch { publisher.run() }
            runCurrent()

            subscriptions.subscriptions = listOf(sim1, sim2)
            subscriptions.emitChange()
            runCurrent()
            job.cancel()

            val lists = session.sentFrames.filter { it.hasSimList() }.map { it.simList.subscriptionsList }
            assertEquals(listOf(listOf(1), listOf(1, 2)), lists.map { subs -> subs.map { it.subscriptionId } })
            assertEquals(listOf("Carrier A", "Carrier B"), lists.last().map { it.displayName })
            assertEquals(listOf(0, 1), lists.last().map { it.slotIndex })
        }

    private fun TestScope.sendUntilDispatched(
        handler: SendSmsHandler,
        request: SendSmsRequest,
    ) {
        val job = launch { handler.handle(request) }
        runCurrent()
        job.cancel()
    }

    private fun statuses(session: FakeTandemSession) =
        session.sentFrames.filter { it.hasSendSmsStatus() }.map { it.sendSmsStatus.state to it.sendSmsStatus.errorCode }

    private fun request(subscriptionId: Int = 0) =
        sendSmsRequest {
            clientMessageId = "client-1"
            address = "+41790000000"
            body = "hello"
            this.subscriptionId = subscriptionId
        }

    private fun handler(
        scope: TestScope,
        subscriptions: SubscriptionSource,
        sender: SmsSender,
        session: FakeTandemSession = FakeTandemSession(),
    ): SendSmsHandler {
        val scheduler = scope.testScheduler
        return SendSmsHandler(
            sender = sender,
            source = FakeSmsSource(),
            session = session,
            permission = SendSmsPermission { true },
            subscriptions = subscriptions,
            results = MutableSharedFlow(extraBufferCapacity = 64),
            elapsed = FakeElapsedRealtime(scheduler),
            ioDispatcher = StandardTestDispatcher(scheduler),
        )
    }
}
