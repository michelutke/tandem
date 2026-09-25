package dev.tandem.core.protocol.flowcontrol

import dev.tandem.protocol.v1.Channel
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class CreditLedgerTest {
    @Test
    fun creditLedger_newLedger_balanceEqualsSpecInitialGrant() {
        val cap = CreditCaps.capFor(Channel.CHANNEL_FILES)

        val ledger = CreditLedger(cap)

        assertEquals(cap, ledger.balance)
    }

    @Test
    fun creditLedger_consumeBeyondBalance_returnsInsufficientBalanceUnchanged() {
        val ledger = CreditLedger(cap = 4)

        val result = ledger.consume(5)

        assertEquals(CreditLedger.ConsumeResult.Insufficient, result)
        assertEquals(4, ledger.balance)
    }

    @Test
    fun creditLedger_consumeExactBalance_balanceZeroNeverNegative() {
        val ledger = CreditLedger(cap = 4)

        val result = ledger.consume(4)

        assertEquals(CreditLedger.ConsumeResult.Ok(0), result)
        assertEquals(0, ledger.balance)

        val furtherConsume = ledger.consume(1)

        assertEquals(CreditLedger.ConsumeResult.Insufficient, furtherConsume)
        assertEquals(0, ledger.balance)
    }

    @Test
    fun creditLedger_grantAboveMax_reportsOverflow() {
        val ledger = CreditLedger(cap = 4)
        ledger.consume(1)

        val result = ledger.applyGrant(2)

        assertEquals(CreditLedger.GrantResult.Overflow, result)
        assertEquals(3, ledger.balance)
    }

    @Test
    fun creditLedger_grantWithinMax_restoresBalance() {
        val ledger = CreditLedger(cap = 4)
        ledger.consume(3)

        val result = ledger.applyGrant(3)

        assertEquals(CreditLedger.GrantResult.Ok(4), result)
        assertEquals(4, ledger.balance)
    }

    @Test
    fun creditLedger_consumeNonPositiveAmount_throwsIllegalArgumentException() {
        val ledger = CreditLedger(cap = 4)

        assertThrows(IllegalArgumentException::class.java) { ledger.consume(0) }
        assertThrows(IllegalArgumentException::class.java) { ledger.consume(-1) }
    }

    @Test
    fun creditLedger_grantNonPositiveAmount_throwsIllegalArgumentException() {
        val ledger = CreditLedger(cap = 4)

        assertThrows(IllegalArgumentException::class.java) { ledger.applyGrant(0) }
        assertThrows(IllegalArgumentException::class.java) { ledger.applyGrant(-1) }
    }

    @Test
    fun creditLedger_capOutsideProtocolMax_throwsIllegalArgumentException() {
        assertThrows(IllegalArgumentException::class.java) { CreditLedger(cap = 0) }
        assertThrows(IllegalArgumentException::class.java) { CreditLedger(cap = CreditCaps.PROTOCOL_MAX + 1) }
    }

    @Test
    fun creditCaps_controlChannel_throwsIllegalArgumentException() {
        assertThrows(IllegalArgumentException::class.java) { CreditCaps.capFor(Channel.CHANNEL_CONTROL) }
    }
}
