package dev.tandem.core.transport

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Reflection tests over [TandemSession] and [FakeTandemSession] (E12-11; `docs/planning/backlog/phase-1.yaml`
 * E12-11's `tdd:` list): [TandemSession] must stay transport-agnostic, so no future USB transport
 * (F-10.3) implementation ever has to depend on TLS types, and (Cycle 8, D-67) no channel-binding
 * or exporter API of any kind may leak through this seam — that value is an in-band `PairChallenge`/
 * `RotationChallenge` read from an ordinary [dev.tandem.protocol.v1.Envelope] by the pairing and
 * key-rotation layers, never exposed here.
 */
class TandemSessionInterfaceTest {
    @Test
    fun tandemSessionInterface_reflectedSignatures_noSslOrConscryptTypes() {
        val signatures = TandemSession::class.java.declaredMethods.map { it.toGenericString() }
        for (signature in signatures) {
            assertTrue(!signature.contains("javax.net.ssl"), "$signature references javax.net.ssl")
            assertTrue(!signature.contains("org.conscrypt"), "$signature references org.conscrypt")
        }
    }

    @Test
    fun tandemSessionInterface_reflectedSignatures_noChannelBindingOrExporterMember() {
        val forbidden = listOf("channelbinding", "exporter")
        val members =
            TandemSession::class.java.declaredMethods.map { it.name } +
                FakeTandemSession::class.java.declaredMethods.map { it.name } +
                FakeTandemSession::class.java.declaredFields.map { it.name }
        for (member in members) {
            val lower = member.lowercase()
            for (needle in forbidden) {
                assertTrue(!lower.contains(needle), "$member looks like a channel-binding/exporter member")
            }
        }
    }
}
