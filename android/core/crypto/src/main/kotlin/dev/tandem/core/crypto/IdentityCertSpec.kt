package dev.tandem.core.crypto

import java.math.BigInteger
import java.security.SecureRandom
import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit
import javax.security.auth.x500.X500Principal

/**
 * Fixed subject for every identity certificate (E10-02). Carries no meaningful identity — never
 * `Build.MODEL`, a device name, a serial number or an account name — by design (out of scope,
 * `docs/planning/backlog/phase-1.yaml` E10 epic).
 */
const val IDENTITY_CERT_SUBJECT = "CN=Tandem Identity"

/** RFC 5280's conventional "no well-defined expiration date" value. */
private val NOT_AFTER: Instant = Instant.parse("9999-12-31T23:59:59Z")

private const val SERIAL_NUMBER_BYTES = 16

/**
 * Parameters for the self-signed identity certificate (E10-02), shared by the real
 * `AndroidKeyStoreIdentityKeyStore` (passed to `KeyGenParameterSpec.setCertificateSubject`/
 * `setCertificateSerialNumber`/`setCertificateNotBefore`/`setCertificateNotAfter`, which the real
 * Keystore signs into a certificate at key-generation time) and `SoftwareIdentityKeyStore`'s
 * hand-built DER certificate (E10-15), so both platforms and JVM `unit:` tests exercise the exact
 * same values.
 */
data class IdentityCertSpec(
    val subject: X500Principal,
    val notBefore: Instant,
    val notAfter: Instant,
    val serialNumber: BigInteger,
) {
    companion object {
        /** [clock] is the injected time seam (E00-18); [random] is a seam only for testability. */
        fun generate(
            clock: Clock,
            random: SecureRandom = SecureRandom(),
        ): IdentityCertSpec {
            val serialBytes = ByteArray(SERIAL_NUMBER_BYTES)
            random.nextBytes(serialBytes)
            return IdentityCertSpec(
                subject = X500Principal(IDENTITY_CERT_SUBJECT),
                notBefore = clock.instant().minus(1, ChronoUnit.DAYS),
                notAfter = NOT_AFTER,
                serialNumber = BigInteger(1, serialBytes),
            )
        }
    }
}
