package dev.tandem.core.discovery

import app.cash.turbine.test
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * NsdServiceDiscovery tests (E21-04; `docs/planning/backlog/phase-2.yaml` E21-04's `tdd:` list).
 * Every [NsdServiceDiscovery] here is built with a `StandardTestDispatcher` sharing `runTest`'s own
 * `TestCoroutineScheduler` (E00-18), so [ResolveRetryPolicy]'s backoff `delay`s advance in virtual
 * time; [FakeNsdSource] never touches `android.net.nsd.NsdManager`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NsdServiceDiscoveryTest {
    private val service = NsdServiceRef("mac-1", NsdServiceDiscovery.SERVICE_TYPE)

    @Test
    fun nsdBrowser_resolveFailsTwiceThenSucceeds_emitsResolvedAfterBackoff() =
        runTest {
            val source = FakeNsdSource()
            source.scriptResolve(
                service,
                ResolveOutcome.Failure(transient = true),
                ResolveOutcome.Failure(transient = true),
                ResolveOutcome.Success(host = "192.168.1.5", port = 5353, txtRecords = mapOf("v" to "1")),
            )
            val discovery = NsdServiceDiscovery(source, StandardTestDispatcher(testScheduler))

            discovery.browse().test {
                val start = testScheduler.currentTime
                source.emit(NsdBrowseEvent.ServiceFound(service))
                advanceUntilIdle()
                assertEquals(DiscoveryEvent.Found("mac-1"), awaitItem())

                val resolved = awaitItem()

                assertEquals(
                    DiscoveryEvent.Resolved(ResolvedService("mac-1", "192.168.1.5", 5353, mapOf("v" to "1"))),
                    resolved,
                )
                // Two backoff waits (E21-04's `ResolveRetryPolicy`) really elapsed before the
                // third, successful attempt -- not an immediate synchronous retry.
                assertTrue(testScheduler.currentTime - start >= 750)
                assertEquals(listOf(service, service, service), source.resolveAttempts)

                cancelAndIgnoreRemainingEvents()
            }
        }

    @Test
    fun nsdBrowser_resolveRetriesExhausted_browseSessionStaysActive() =
        runTest {
            val source = FakeNsdSource()
            val exhausted = NsdServiceRef("mac-exhausted", NsdServiceDiscovery.SERVICE_TYPE)
            source.scriptResolve(
                exhausted,
                ResolveOutcome.Failure(transient = true),
                ResolveOutcome.Failure(transient = true),
                ResolveOutcome.Failure(transient = true),
            )
            val other = NsdServiceRef("mac-other", NsdServiceDiscovery.SERVICE_TYPE)
            source.scriptResolve(other, ResolveOutcome.Success("192.168.1.9", 6000, mapOf("v" to "1")))
            val discovery = NsdServiceDiscovery(source, StandardTestDispatcher(testScheduler))

            discovery.browse().test {
                source.emit(NsdBrowseEvent.ServiceFound(exhausted))
                advanceUntilIdle()
                assertEquals(DiscoveryEvent.Found("mac-exhausted"), awaitItem())
                assertEquals(3, source.resolveAttempts.count { it == exhausted })

                // No Resolved event ever arrives for the exhausted service; a later find for a
                // different service still resolves normally, proving the session stayed active.
                source.emit(NsdBrowseEvent.ServiceFound(other))
                advanceUntilIdle()
                assertEquals(DiscoveryEvent.Found("mac-other"), awaitItem())
                assertEquals(
                    DiscoveryEvent.Resolved(ResolvedService("mac-other", "192.168.1.9", 6000, mapOf("v" to "1"))),
                    awaitItem(),
                )

                cancelAndIgnoreRemainingEvents()
            }
        }

    @Test
    fun nsdBrowser_serviceLost_removedFromCandidates() =
        runTest {
            val source = FakeNsdSource()
            source.scriptResolve(service, ResolveOutcome.Success("192.168.1.5", 5353, mapOf("v" to "1")))
            val discovery = NsdServiceDiscovery(source, StandardTestDispatcher(testScheduler))
            val candidates = mutableMapOf<String, ResolvedService>()

            discovery.browse().test {
                source.emit(NsdBrowseEvent.ServiceFound(service))
                advanceUntilIdle()
                awaitItem() // Found

                val resolved = awaitItem() as DiscoveryEvent.Resolved
                candidates[resolved.candidate.serviceName] = resolved.candidate
                assertTrue(candidates.containsKey("mac-1"))

                source.emit(NsdBrowseEvent.ServiceLost(service))
                advanceUntilIdle()
                val lost = awaitItem() as DiscoveryEvent.Lost
                candidates.remove(lost.serviceName)

                assertFalse(candidates.containsKey("mac-1"))
                cancelAndIgnoreRemainingEvents()
            }
        }
}
