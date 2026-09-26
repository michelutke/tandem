package dev.tandem.core.crypto

import android.security.keystore.KeyPermanentlyInvalidatedException
import app.cash.turbine.test
import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.interfaces.ECPrivateKey

class IdentityBootstrapperTest {
    private val clock = TestClock(TestCoroutineScheduler())

    @Test
    fun bootstrapIdentity_noExistingAlias_generatesExactlyOnce() {
        val counting = CountingGetOrCreateIdentityKeyStore(SoftwareIdentityKeyStore(clock))
        val bootstrapper = IdentityBootstrapper(counting)

        val handle = bootstrapper.bootstrapIdentity()

        assertEquals(1, counting.getOrCreateCallCount)
        assertNotNull(handle.publicKey)
        assertNotNull(handle.privateKey)
    }

    @Test
    fun bootstrapIdentity_signThrowsPermanentlyInvalidated_emitsIdentityResetAndNewPublicKey() =
        runTest {
            val software = SoftwareIdentityKeyStore(clock)
            val originalPublicKey = software.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true).publicKey
            val poisoned = SignPoisoningIdentityKeyStore(software)
            val events = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
            val bootstrapper = IdentityBootstrapper(poisoned, onIdentityReset = { events.tryEmit(Unit) })

            events.test {
                val handle = bootstrapper.bootstrapIdentity()

                awaitItem()
                assertNotEquals(originalPublicKey, handle.publicKey)
                expectNoEvents()
            }
        }

    @Test
    fun bootstrapIdentity_aliasMissing_emitsIdentityResetAndRegenerates() =
        runTest {
            val store = SoftwareIdentityKeyStore(clock)
            val events = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
            val bootstrapper = IdentityBootstrapper(store, onIdentityReset = { events.tryEmit(Unit) })

            events.test {
                val handle = bootstrapper.bootstrapIdentity()

                awaitItem()
                assertNotNull(handle.publicKey)
                expectNoEvents()
            }
        }

    @Test
    fun bootstrapIdentity_afterReset_requiresRePairTrueUntilPairingSucceeds() {
        val store = SoftwareIdentityKeyStore(clock)
        val bootstrapper = IdentityBootstrapper(store)

        bootstrapper.bootstrapIdentity()
        assertTrue(bootstrapper.requiresRePair)

        bootstrapper.notifyPairingSucceeded()
        assertFalse(bootstrapper.requiresRePair)
    }

    @Test
    fun bootstrapIdentity_existingUsableKey_samePublicKeyNoResetEvent() =
        runTest {
            val store = SoftwareIdentityKeyStore(clock)
            val existing = store.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
            val events = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
            val bootstrapper = IdentityBootstrapper(store, onIdentityReset = { events.tryEmit(Unit) })

            val handle = bootstrapper.bootstrapIdentity()

            assertEquals(existing.publicKey, handle.publicKey)
            assertFalse(bootstrapper.requiresRePair)
            events.test {
                expectNoEvents()
            }
        }

    private class CountingGetOrCreateIdentityKeyStore(
        private val delegate: IdentityKeyStore,
    ) : IdentityKeyStore {
        var getOrCreateCallCount = 0
            private set

        override fun getOrCreate(
            alias: String,
            preferStrongBox: Boolean,
        ): KeyHandle {
            getOrCreateCallCount++
            return delegate.getOrCreate(alias, preferStrongBox)
        }

        override fun get(alias: String): KeyHandle? = delegate.get(alias)

        override fun delete(alias: String) = delegate.delete(alias)
    }

    /**
     * Decorator (E10-04's seam) whose [get] returns a handle wrapping the real private key in
     * [PoisonedPrivateKey], which throws [KeyPermanentlyInvalidatedException] when the JCA provider
     * reads the private scalar during `Signature.initSign` — simulating AndroidKeyStore's real
     * failure mode for an invalidated key without needing a real Keystore.
     */
    private class SignPoisoningIdentityKeyStore(
        private val delegate: IdentityKeyStore,
    ) : IdentityKeyStore {
        override fun getOrCreate(
            alias: String,
            preferStrongBox: Boolean,
        ): KeyHandle = delegate.getOrCreate(alias, preferStrongBox)

        override fun get(alias: String): KeyHandle? =
            delegate.get(alias)?.let { handle ->
                handle.copy(privateKey = PoisonedPrivateKey(handle.privateKey as ECPrivateKey))
            }

        override fun delete(alias: String) = delegate.delete(alias)
    }

    private class PoisonedPrivateKey(
        private val real: ECPrivateKey,
    ) : ECPrivateKey by real {
        override fun getS() = throw KeyPermanentlyInvalidatedException()

        override fun getEncoded(): ByteArray = throw KeyPermanentlyInvalidatedException()
    }
}
