package dev.tandem.harness.jvmclient.latency

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.abs

/** E30-14 tdd: unit: clockOffsetEstimator_known250msSkew_correctedWithin5ms */
class ClockOffsetEstimatorTest {
    @Test
    fun clockOffsetEstimator_known250msSkew_correctedWithin5ms() {
        val knownSkewMillis = 250L
        val networkDelayMillis = 20L
        val t0LocalSend = 1_000_000L
        val t1RemoteReceive = t0LocalSend + networkDelayMillis + knownSkewMillis
        val t2RemoteSend = t1RemoteReceive + 5L
        val t3LocalReceive = t2RemoteSend + networkDelayMillis - knownSkewMillis

        val estimatedOffset =
            ClockOffsetEstimator.estimateOffsetMillis(
                t0LocalSend = t0LocalSend,
                t1RemoteReceive = t1RemoteReceive,
                t2RemoteSend = t2RemoteSend,
                t3LocalReceive = t3LocalReceive,
            )

        assertTrue(
            abs(estimatedOffset - knownSkewMillis) <= 5L,
            "expected offset within 5ms of $knownSkewMillis, got $estimatedOffset",
        )
    }

    @Test
    fun estimateOffsetMillis_noSkewSymmetricDelay_estimatesZero() {
        val t0 = 5_000L
        val t1 = 5_010L
        val t2 = 5_015L
        val t3 = 5_025L

        assertTrue(
            abs(ClockOffsetEstimator.estimateOffsetMillis(t0, t1, t2, t3)) <= 1L,
        )
    }
}
