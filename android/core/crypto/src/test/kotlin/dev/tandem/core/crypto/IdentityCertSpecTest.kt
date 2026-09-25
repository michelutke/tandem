package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.time.Instant
import javax.security.auth.x500.X500Principal

class IdentityCertSpecTest {
    private val clock = TestClock(TestCoroutineScheduler())

    @Test
    fun identityCertSpec_subject_equalsFixedConstantOnly() {
        val spec = IdentityCertSpec.generate(clock)

        assertEquals(X500Principal(IDENTITY_CERT_SUBJECT), spec.subject)
    }

    @Test
    fun identityCertSpec_validity_notAfterIs99991231AndCaFalse() {
        val handle = SoftwareIdentityKeyStore(clock).getOrCreate("alias", preferStrongBox = true)

        assertEquals(Instant.parse("9999-12-31T23:59:59Z"), handle.certificate.notAfter.toInstant())
        assertEquals(-1, handle.certificate.basicConstraints)
    }
}
