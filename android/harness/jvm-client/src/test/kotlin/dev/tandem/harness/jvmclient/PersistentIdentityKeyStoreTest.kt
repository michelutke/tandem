package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.spkiFingerprint
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.time.Clock

/** E15-21 tdd: unit: jvmHarnessClient_restartProcess_sameSoftwareIdentityLoaded */
class PersistentIdentityKeyStoreTest {
    @Test
    fun jvmHarnessClient_restartProcess_sameSoftwareIdentityLoaded() {
        val identityFile = Files.createTempFile("harness-identity-test", ".bin").toFile().apply { delete() }

        val alias = PersistentIdentityKeyStore.IDENTITY_ALIAS
        val firstProcessStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
        val firstHandle = firstProcessStore.getOrCreate(alias, preferStrongBox = false)
        val firstFingerprint = spkiFingerprint(firstHandle.certificate.publicKey.encoded)

        // Simulates a process restart: a brand new PersistentIdentityKeyStore instance, backed by
        // the same file, sharing no in-memory state with `firstProcessStore`.
        val secondProcessStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
        val secondHandle = secondProcessStore.getOrCreate(alias, preferStrongBox = false)
        val secondFingerprint = spkiFingerprint(secondHandle.certificate.publicKey.encoded)

        assertArrayEquals(firstFingerprint.bytes, secondFingerprint.bytes)
    }
}
