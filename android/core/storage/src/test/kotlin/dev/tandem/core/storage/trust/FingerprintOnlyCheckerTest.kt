package dev.tandem.core.storage.trust

import dev.tandem.core.crypto.SpkiFingerprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Method
import java.lang.reflect.Modifier

/**
 * E13-10: Reflection-based regression test asserting every public trust-store lookup/delete
 * method takes [SpkiFingerprint] as its sole key (invariant 3: "Trust is bound to SPKI
 * fingerprints only"; deviceId is a display field only, never a key; no IP/hostname parameter).
 *
 * The checker is itself tested against fixture interfaces that violate the rule.
 */
class FingerprintOnlyCheckerTest {
    private val checker = FingerprintOnlyChecker()

    @Test
    fun trustStoreApiReflection_everyLookupMethod_takesSpkiFingerprintOnly() {
        val violations = checker.check(TrustStore::class.java)
        assertTrue(
            "TrustStore API should not have fingerprint-only violations. Found: $violations",
            violations.isEmpty(),
        )
    }

    @Test
    fun fingerprintOnlyChecker_fixtureWithHostLookup_reportsViolation() {
        val violations = checker.check(FixtureTrustStoreWithHostLookup::class.java)
        assertEquals(
            "Should report violation for getByHost method",
            1,
            violations.size,
        )
        assertTrue(
            "Violation should mention getByHost method",
            violations[0].contains("getByHost"),
        )
    }

    @Test
    fun fingerprintOnlyChecker_fixtureWithDeviceIdLookup_reportsViolation() {
        val violations = checker.check(FixtureTrustStoreWithDeviceIdLookup::class.java)
        assertEquals(
            "Should report violation for getByDeviceId method",
            1,
            violations.size,
        )
        assertTrue(
            "Violation should mention getByDeviceId method",
            violations[0].contains("getByDeviceId"),
        )
    }

    // Fixture: trust store interface with hostname-based lookup (violates invariant 3)
    private interface FixtureTrustStoreWithHostLookup {
        fun getByHost(host: String): PeerRecord?
    }

    // Fixture: trust store interface with device-ID-based lookup (violates invariant 3)
    private interface FixtureTrustStoreWithDeviceIdLookup {
        fun getByDeviceId(id: String): PeerRecord?
    }
}

/**
 * Reflection-based checker that validates a trust-store interface for fingerprint-only keying.
 * Reports violations where lookup/delete methods take parameters other than SpkiFingerprint
 * or String (representing base64url fingerprints).
 *
 * Handles Kotlin suspend functions, which are compiled with an extra Continuation parameter.
 */
internal class FingerprintOnlyChecker {
    private val lookupDeleteMethods = setOf("get", "delete", "unpair")

    fun check(clazz: Class<*>): List<String> {
        val violations = mutableListOf<String>()

        clazz.methods
            .filter { Modifier.isPublic(it.modifiers) && isLookupOrDeleteMethod(it) }
            .forEach { method ->
                if (!isValidFingerprintOnlyMethod(method)) {
                    val paramList = method.parameters.joinToString { "${it.name}: ${it.type.simpleName}" }
                    violations.add(
                        "${clazz.simpleName}.${method.name}: lookup/delete methods must take " +
                            "only SpkiFingerprint as sole key parameter. Found: $paramList",
                    )
                }
            }

        return violations
    }

    private fun isLookupOrDeleteMethod(method: Method): Boolean {
        // Skip methods from Object class
        if (method.declaringClass == Object::class.java) {
            return false
        }
        return lookupDeleteMethods.any { method.name.startsWith(it) }
    }

    private fun isValidFingerprintOnlyMethod(method: Method): Boolean {
        val params = method.parameters

        // Filter out Continuation parameter (added by Kotlin suspend functions at bytecode level)
        // Continuation is the last parameter with type containing "Continuation"
        val filteredParams = params.filter { !it.type.name.contains("Continuation") }

        // Public lookup/delete methods should have exactly 1 non-Continuation parameter
        if (filteredParams.size != 1) {
            return false
        }

        val paramType = filteredParams[0].type
        // Public methods must take SpkiFingerprint; internal DAO methods may take String for base64Url
        return paramType == SpkiFingerprint::class.java
    }
}
