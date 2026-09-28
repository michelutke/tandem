package dev.tandem.core.discovery

import dev.tandem.core.crypto.DiscoveryRotatingId
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.DiscoveryTxtRecord
import java.time.Clock

/**
 * Recognizes a resolved `_tandem._tcp` service's advertised rotating id (SPEC.md "Discovery TXT
 * record") against a list of already-paired Macs' SPKI fingerprints (E21-05).
 *
 * Invariant 3 (CLAUDE.md): a [PairedMacMatch] is a connection-candidate hint only, never a trust
 * decision. An attacker who has observed a paired Mac's *current* rotating id can replay it and
 * also match here -- recognition only narrows which resolved service is worth attempting a
 * connection to. The mTLS pin check on the resulting connection attempt (E20-06), not this
 * recognition, is what actually authenticates the peer.
 */
class PairedMacMatcher(
    private val clock: Clock,
) {
    /**
     * Parses [service]'s TXT record and checks its advertised id against every fingerprint in
     * [pairedFingerprints]'s +/-1 day skew window (SPEC.md "Discovery TXT record"). Returns the
     * first match, or `null` if the TXT record is malformed/unsupported or no fingerprint matches.
     * Never throws.
     *
     * [Clock.instant]'s epoch second is zone-agnostic by construction, so the UTC day boundary
     * [DiscoveryRotatingId] derives from it is unaffected by [clock]'s configured time zone --
     * routing through `LocalDate`/`ZonedDateTime` instead would reintroduce that dependency.
     */
    fun match(
        service: ResolvedService,
        pairedFingerprints: List<SpkiFingerprint>,
    ): PairedMacMatch? {
        val parsed = runCatching { DiscoveryTxtRecord.parse(service.txtRecords) }.getOrNull() ?: return null
        val receiverUnixSecondsUtc = clock.instant().epochSecond

        return pairedFingerprints
            .firstOrNull { candidate ->
                val candidateIds = DiscoveryRotatingId.candidateHexIds(candidate.bytes, receiverUnixSecondsUtc)
                parsed.idHex in candidateIds
            }?.let { fingerprint -> PairedMacMatch(fingerprint, service) }
    }
}

/** [fingerprint]'s rotating id matched [service]'s advertised id -- a connection-candidate hint only. */
data class PairedMacMatch(
    val fingerprint: SpkiFingerprint,
    val service: ResolvedService,
)
