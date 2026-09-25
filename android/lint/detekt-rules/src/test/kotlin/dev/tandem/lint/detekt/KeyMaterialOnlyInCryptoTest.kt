package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * E10-14 tdd:
 *   ci: keyMaterialCheck_androidKeyStoreInFeatureFixture_exitsNonZero
 *   ci: keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero (Kotlin side; the Swift side
 *   of this same tdd entry is tools/lint/test/swiftlint_key_material_only_in_crypto_rule_test.sh)
 *
 * Fixtures are permanent files under tools/lint-fixtures/key-material/ (E10-14's acceptance: "no
 * add-and-revert"), read from disk rather than written into a real module and deleted.
 * `keyMaterialCheck_currentTree_exitsZero` is the real `./gradlew detekt` run with `core/crypto`
 * excluded from this rule (android/config/detekt/detekt.yml).
 */
class KeyMaterialOnlyInCryptoTest {
    @Test
    fun keyMaterialCheck_androidKeyStoreInFeatureFixture_exitsNonZero() {
        val findings =
            KeyMaterialOnlyInCrypto().compileAndLint(
                fixture("android-keystore-in-feature/AndroidKeyStoreFixture.kt"),
            )

        assertEquals(1, findings.size)
        assertEquals("KeyMaterialOnlyInCrypto", findings.single().id)
    }

    @Test
    fun keyMaterialCheck_hmacOutsideCryptoModuleFixture_exitsNonZero() {
        val findings =
            KeyMaterialOnlyInCrypto().compileAndLint(
                fixture("hmac-outside-crypto-module/HmacFixture.kt"),
            )

        assertEquals(1, findings.size)
        assertEquals("KeyMaterialOnlyInCrypto", findings.single().id)
    }

    @Test
    fun keyMaterialOnlyInCrypto_unrelatedKeyStoreCall_detektPasses() {
        val findings =
            KeyMaterialOnlyInCrypto().compileAndLint(
                """
                package dev.tandem.core.transport

                import java.security.KeyStore

                internal fun trustStoreFixture(): KeyStore = KeyStore.getInstance("PKCS12")
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    private fun fixture(relativePath: String): String {
        val repoRoot = File(System.getProperty("user.dir"), "../../..").canonicalFile
        return File(repoRoot, "tools/lint-fixtures/key-material/$relativePath").readText()
    }
}
