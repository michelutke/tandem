package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.contacts.ContactsSource
import dev.tandem.feature.contacts.ContactsSyncSession
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.time.Clock

/** Answers the Mac's CONTACTS sync requests and pushes incremental changes while a session is attached (F-8.3). */
class ContactsFeature(
    private val source: ContactsSource,
    private val ioDispatcher: CoroutineDispatcher,
    private val clock: Clock,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val sync = ContactsSyncSession(source, session, ioDispatcher, clock)
        coroutineScope {
            launch { sync.run() }
            launch { sync.observeChanges() }
        }
    }
}
