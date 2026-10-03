package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

private const val ROTATED_ALIAS = "tandem.identity.v2"

class IdentityBootstrapperRotationTest {
    private val store = SoftwareIdentityKeyStore(TestClock(TestCoroutineScheduler()))

    @Test
    fun bootstrapIdentity_restartAfterRotation_usesRotatedKey(
        @TempDir dir: File,
    ) {
        val file = File(dir, "alias")
        store.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
        val rotated = store.getOrCreate(ROTATED_ALIAS, preferStrongBox = true)
        ActiveIdentityAlias(file).activate(ROTATED_ALIAS)
        store.delete(IDENTITY_KEY_ALIAS)

        val handle = IdentityBootstrapper(store, ActiveIdentityAlias(file)).bootstrapIdentity()

        assertEquals(ROTATED_ALIAS, handle.alias)
        assertEquals(rotated.publicKey, handle.publicKey)
    }

    @Test
    fun bootstrapIdentity_missingAliasFile_usesOriginalKey(
        @TempDir dir: File,
    ) {
        val original = store.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)

        val handle = IdentityBootstrapper(store, ActiveIdentityAlias(File(dir, "alias"))).bootstrapIdentity()

        assertEquals(original.publicKey, handle.publicKey)
    }

    @Test
    fun bootstrapIdentity_persistedAliasKeyMissingOriginalExists_fallsBackWithoutNewIdentity(
        @TempDir dir: File,
    ) {
        val file = File(dir, "alias")
        val original = store.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
        ActiveIdentityAlias(file).activate(ROTATED_ALIAS)
        val bootstrapper = IdentityBootstrapper(store, ActiveIdentityAlias(file))

        val handle = bootstrapper.bootstrapIdentity()

        assertEquals(original.publicKey, handle.publicKey)
        assertFalse(bootstrapper.requiresRePair)
        assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(file).current)
    }
}
