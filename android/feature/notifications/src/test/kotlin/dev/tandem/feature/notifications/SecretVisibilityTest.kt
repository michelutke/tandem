package dev.tandem.feature.notifications

import android.app.Notification
import android.app.Person
import android.content.Context
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.protocol.v1.Visibility
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import java.io.File

// E30-11 tdd:
//   unit: secretVisibility_defaultOptOut_titleIsAppNameAndTextEmpty
//   unit: secretVisibility_defaultOptOutMessagingStyle_sendersListEmpty
//   unit: secretVisibility_optedIn_forwardsOriginalTitleAndText
//   unit: secretVisibility_optInToggledOff_nextPostRedacted
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class SecretVisibilityTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun secretVisibility_defaultOptOut_titleIsAppNameAndTextEmpty() =
        runTest {
            val policy = newPolicy()

            val posted = secretPosted(policy)

            assertEquals("Chat", posted.title)
            assertEquals("", posted.text)
            assertEquals(Visibility.VISIBILITY_SECRET, posted.visibility)
        }

    @Test
    fun secretVisibility_defaultOptOutMessagingStyle_sendersListEmpty() =
        runTest {
            val policy = newPolicy()
            val style = Notification.MessagingStyle(Person.Builder().setName("Me").build())
            style.addMessage("hello", 0L, Person.Builder().setName("Alice").build())
            val notification =
                Notification
                    .Builder(context, CHANNEL_ID)
                    .setStyle(style)
                    .setVisibility(Notification.VISIBILITY_SECRET)
                    .build()

            val posted =
                NotificationMapper.toPosted(
                    sbn(notification),
                    appVersionCode = 1L,
                    appName = "Chat",
                    showSecretContent = policy.showContent.value,
                )

            assertTrue(posted.messagingStyleSendersList.isEmpty())
            assertEquals("", posted.text)
            assertEquals("Chat", posted.title)
        }

    @Test
    fun secretVisibility_optedIn_forwardsOriginalTitleAndText() =
        runTest {
            val policy = newPolicy()
            policy.setShowContent(true)
            runCurrent()

            val posted = secretPosted(policy)

            assertEquals("Alice", posted.title)
            assertEquals("On my way", posted.text)
            assertEquals(Visibility.VISIBILITY_SECRET, posted.visibility)
        }

    @Test
    fun secretVisibility_optInToggledOff_nextPostRedacted() =
        runTest {
            val policy = newPolicy()
            policy.setShowContent(true)
            runCurrent()
            assertEquals("On my way", secretPosted(policy).text)

            policy.setShowContent(false)
            runCurrent()

            val posted = secretPosted(policy)
            assertEquals("Chat", posted.title)
            assertEquals("", posted.text)
        }

    @Test
    fun secretVisibility_defaultIsOff() =
        runTest {
            assertFalse(newPolicy().showContent.value)
        }

    @Test
    fun secretVisibility_publicNotification_unaffectedByOptOut() {
        val notification =
            Notification
                .Builder(context, CHANNEL_ID)
                .setContentTitle("Alice")
                .setContentText("On my way")
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .build()

        val posted =
            NotificationMapper.toPosted(
                sbn(notification),
                appVersionCode = 1L,
                appName = "Chat",
                showSecretContent = false,
            )

        assertEquals("Alice", posted.title)
        assertEquals("On my way", posted.text)
        assertEquals(Visibility.VISIBILITY_PUBLIC, posted.visibility)
    }

    private fun secretPosted(policy: SecretNotificationPolicy) =
        NotificationMapper.toPosted(
            sbn(
                Notification
                    .Builder(context, CHANNEL_ID)
                    .setContentTitle("Alice")
                    .setContentText("On my way")
                    .setVisibility(Notification.VISIBILITY_SECRET)
                    .build(),
            ),
            appVersionCode = 1L,
            appName = "Chat",
            showSecretContent = policy.showContent.value,
        )

    private fun TestScope.newPolicy(): SecretNotificationPolicy {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val file = File(context.filesDir, "secret-policy-${System.nanoTime()}.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(scope = scope) { file }
        return SecretNotificationPolicy(SettingsStore(dataStore), scope)
    }

    @Suppress("DEPRECATION")
    private fun sbn(notification: Notification): StatusBarNotification =
        StatusBarNotification(
            "com.example.chat",
            "com.example.chat",
            1,
            "tag",
            Process.myUid(),
            Process.myPid(),
            0,
            notification,
            Process.myUserHandle(),
            System.currentTimeMillis(),
        )

    private companion object {
        const val CHANNEL_ID = "test-channel"
    }
}
