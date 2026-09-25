package dev.tandem.core.protocol.flowcontrol

/**
 * Pure per-channel credit-flow-control accounting (SPEC.md #channels-and-flow-control-credits,
 * E01-04; `docs/planning/decisions.md` D-64). Tracks this side's outgoing-direction balance for
 * a single feature channel. No coroutines, no I/O: the suspending multiplexer built on top of
 * this (E11-07) is the layer that pauses sends and closes the connection on a violation; this
 * class only ever reports what happened.
 *
 * A new ledger starts at [cap] (the initial grant). [consume] models the channel's
 * application-level consumer taking a frame out of the receive buffer — SPEC.md: credit is
 * returned to the sender only at that point, not at decode. [applyGrant] models this side
 * receiving a peer's `CreditGrant`. Per D-64, a grant that would push the balance above [cap] is
 * reported as [GrantResult.Overflow] rather than silently clamped: clamping would leave the peer
 * permanently unable to use credit it believes it holds, so the caller must close the connection
 * with `CREDIT_VIOLATION` instead.
 *
 * @param cap this channel's chosen cap (SPEC.md: receiver-chosen, at most [CreditCaps.PROTOCOL_MAX]).
 *   See [CreditCaps] for Tandem's own per-channel choices.
 */
class CreditLedger(
    private val cap: Int,
) {
    init {
        require(cap in 1..CreditCaps.PROTOCOL_MAX) {
            "cap must be in 1..${CreditCaps.PROTOCOL_MAX}, was $cap"
        }
    }

    /** This channel's current outstanding-credit balance. Never negative, never above [cap]. */
    var balance: Int = cap
        private set

    /** Result of [consume]. */
    sealed class ConsumeResult {
        /** The consume succeeded; [balance] is the ledger's balance after consuming. */
        data class Ok(
            val balance: Int,
        ) : ConsumeResult()

        /** [amount] exceeded the current balance; the balance is unchanged. */
        data object Insufficient : ConsumeResult()
    }

    /** Result of [applyGrant]. */
    sealed class GrantResult {
        /** The grant succeeded; [balance] is the ledger's balance after applying it. */
        data class Ok(
            val balance: Int,
        ) : GrantResult()

        /** The grant would have pushed the balance above [cap]; the balance is unchanged (D-64: never clamped). */
        data object Overflow : GrantResult()
    }

    /**
     * Records that [amount] credits' worth of frames were taken by this channel's
     * application-level consumer.
     *
     * @throws IllegalArgumentException if [amount] is not positive: consuming zero or a negative
     *   number of frames is never a meaningful event on this channel, so it is rejected as a
     *   caller error rather than silently accepted or treated as a no-op.
     */
    fun consume(amount: Int): ConsumeResult {
        require(amount > 0) { "consume amount must be positive, was $amount" }
        if (amount > balance) return ConsumeResult.Insufficient
        balance -= amount
        return ConsumeResult.Ok(balance)
    }

    /**
     * Applies a `CreditGrant.amount` of [amount] credits received from the peer.
     *
     * @throws IllegalArgumentException if [amount] is not positive. SPEC.md treats a
     *   `CreditGrant.amount` of 0 as a well-formed no-op, not a violation — the caller (E11-07)
     *   must recognize that case itself and skip calling [applyGrant] rather than rely on this
     *   pure-accounting layer to special-case it; a negative amount never occurs on the wire
     *   (`amount` is unsigned) and indicates a caller bug.
     */
    fun applyGrant(amount: Int): GrantResult {
        require(amount > 0) { "grant amount must be positive, was $amount" }
        val newBalance = balance + amount
        if (newBalance > cap) return GrantResult.Overflow
        balance = newBalance
        return GrantResult.Ok(balance)
    }
}
