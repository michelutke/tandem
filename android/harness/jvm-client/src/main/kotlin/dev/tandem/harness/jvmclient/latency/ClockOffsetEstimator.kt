package dev.tandem.harness.jvmclient.latency

/**
 * E30-14 (same method as E61-08): estimates the remote clock's offset from this side's clock from
 * a single round trip's four timestamps -- the classic NTP formula. Pure function: no socket, no
 * clock, no side effect.
 *
 * `t0` this side sends its probe; `t1` the remote side receives it (remote clock); `t2` the
 * remote side sends its reply (remote clock); `t3` this side receives the reply (this side's
 * clock). All four are epoch milliseconds. The estimate assumes the outbound and return network
 * delays are equal (`(t1 - t0) == (t3 - t2)`); any difference between them shows up as error in
 * the estimate.
 */
object ClockOffsetEstimator {
    /**
     * Positive when the remote clock reads ahead of this side's clock: adding the result to a
     * timestamp taken on this side converts it into the remote clock's frame, and subtracting it
     * from a remote timestamp converts it back into this side's frame.
     */
    fun estimateOffsetMillis(
        t0LocalSend: Long,
        t1RemoteReceive: Long,
        t2RemoteSend: Long,
        t3LocalReceive: Long,
    ): Long = ((t1RemoteReceive - t0LocalSend) + (t2RemoteSend - t3LocalReceive)) / 2
}
