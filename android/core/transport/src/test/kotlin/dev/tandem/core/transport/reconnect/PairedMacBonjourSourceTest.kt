package dev.tandem.core.transport.reconnect

import dev.tandem.core.crypto.DiscoveryRotatingId
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.discovery.DiscoveryEvent
import dev.tandem.core.discovery.FakeServiceDiscovery
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.PermissionGatedServiceDiscovery
import dev.tandem.core.discovery.ResolvedService
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset

/**
 * [PairedMacBonjourSource] tests (E20-06): the production [BonjourCandidateSource], collecting
 * [FakeServiceDiscovery] (E21-04) events through [PairedMacMatcher] (E21-05).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PairedMacBonjourSourceTest {
    private val now = Instant.parse("2025-06-15T12:00:00Z")
    private val pairedFingerprint = SpkiFingerprint(ByteArray(32) { it.toByte() })

    private fun matchingService(serviceName: String = "mac-1") =
        ResolvedService(
            serviceName = serviceName,
            host = "192.168.1.5",
            port = 5353,
            txtRecords =
                mapOf(
                    "v" to "1",
                    "id" to
                        DiscoveryRotatingId.computeHex(
                            pairedFingerprint.bytes,
                            DiscoveryRotatingId.dayIndex(now.epochSecond),
                        ),
                ),
        )

    @Test
    fun pairedMacBonjourSource_localNetworkPermissionMissing_snapshotStaysEmpty() =
        runTest {
            val discovery = FakeServiceDiscovery()
            val source =
                PairedMacBonjourSource(
                    discovery = PermissionGatedServiceDiscovery(discovery) { false },
                    matcher = PairedMacMatcher(Clock.fixed(now, ZoneOffset.UTC)),
                    pairedFingerprints = { listOf(pairedFingerprint) },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )

            source.start()
            discovery.emit(DiscoveryEvent.Resolved(matchingService()))
            runCurrent()

            assertTrue(source.snapshot().isEmpty())
            source.close()
        }

    @Test
    fun pairedMacBonjourSource_resolvedMatchingService_appearsInSnapshot() =
        runTest {
            val discovery = FakeServiceDiscovery()
            val source =
                PairedMacBonjourSource(
                    discovery = discovery,
                    matcher = PairedMacMatcher(Clock.fixed(now, ZoneOffset.UTC)),
                    pairedFingerprints = { listOf(pairedFingerprint) },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )

            source.start()
            discovery.emit(DiscoveryEvent.Resolved(matchingService()))
            runCurrent()

            assertEquals(listOf(CandidateAddress("192.168.1.5", 5353)), source.snapshot())
        }

    @Test
    fun pairedMacBonjourSource_lostService_removedFromSnapshot() =
        runTest {
            val discovery = FakeServiceDiscovery()
            val source =
                PairedMacBonjourSource(
                    discovery = discovery,
                    matcher = PairedMacMatcher(Clock.fixed(now, ZoneOffset.UTC)),
                    pairedFingerprints = { listOf(pairedFingerprint) },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )

            source.start()
            discovery.emit(DiscoveryEvent.Resolved(matchingService()))
            runCurrent()
            assertTrue(source.snapshot().isNotEmpty())

            discovery.emit(DiscoveryEvent.Lost("mac-1"))
            runCurrent()

            assertEquals(emptyList<CandidateAddress>(), source.snapshot())
        }

    @Test
    fun pairedMacBonjourSource_resolvedUnrecognizedService_neverAppearsInSnapshot() =
        runTest {
            val discovery = FakeServiceDiscovery()
            val source =
                PairedMacBonjourSource(
                    discovery = discovery,
                    matcher = PairedMacMatcher(Clock.fixed(now, ZoneOffset.UTC)),
                    pairedFingerprints = { emptyList() },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )

            source.start()
            discovery.emit(DiscoveryEvent.Resolved(matchingService()))
            runCurrent()

            assertEquals(emptyList<CandidateAddress>(), source.snapshot())
        }
}
