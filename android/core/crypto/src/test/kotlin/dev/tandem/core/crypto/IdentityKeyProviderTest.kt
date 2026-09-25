package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class IdentityKeyProviderTest {
    private val clock = TestClock(TestCoroutineScheduler())

    @Test
    fun identityKeyProvider_strongBoxUnavailable_retriesOnceWithoutStrongBox() {
        val software = SoftwareIdentityKeyStore(clock)
        software.failNextGenerate(InjectedKeyStoreFailure.STRONGBOX_UNAVAILABLE)
        val counting = CountingIdentityKeyStore(software)
        val provider = IdentityKeyProvider(counting, logSecurityLevel = {})

        val handle = provider.getOrCreateIdentityKey()

        assertEquals(2, counting.getOrCreateCallCount)
        assertEquals(IDENTITY_KEY_ALIAS, handle.alias)
        assertEquals(SecurityLevel.SOFTWARE, handle.securityLevel)
    }

    @Test
    fun identityKeyProvider_bothGenerationsFail_throwsGenerationFailedNoSoftwareKey() {
        val store = AlwaysFailingIdentityKeyStore()
        val provider = IdentityKeyProvider(store)

        assertThrows(IdentityKeyError.GenerationFailed::class.java) {
            provider.getOrCreateIdentityKey()
        }
        assertNull(store.get(IDENTITY_KEY_ALIAS))
    }

    @Test
    fun identityKeyProvider_strongBoxFallback_logsSecurityLevelWithoutKeyBytes() {
        val software = SoftwareIdentityKeyStore(clock)
        software.failNextGenerate(InjectedKeyStoreFailure.STRONGBOX_UNAVAILABLE)
        val loggedLevels = mutableListOf<SecurityLevel>()
        val provider = IdentityKeyProvider(software, logSecurityLevel = loggedLevels::add)

        val handle = provider.getOrCreateIdentityKey()

        assertEquals(listOf(handle.securityLevel), loggedLevels)
    }

    @Test
    fun identityKeyProvider_calledTwice_returnsSameKeyWithoutRegenerating() {
        val provider = IdentityKeyProvider(SoftwareIdentityKeyStore(clock))

        val first = provider.getOrCreateIdentityKey()
        val second = provider.getOrCreateIdentityKey()

        assertSame(first, second)
    }

    private class CountingIdentityKeyStore(
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

    private class AlwaysFailingIdentityKeyStore : IdentityKeyStore {
        override fun getOrCreate(
            alias: String,
            preferStrongBox: Boolean,
        ): KeyHandle = throw StrongBoxUnavailableException()

        override fun get(alias: String): KeyHandle? = null

        override fun delete(alias: String) = Unit
    }
}
