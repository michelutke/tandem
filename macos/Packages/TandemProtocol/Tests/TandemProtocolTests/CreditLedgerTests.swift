import Testing
@testable import TandemProtocol

@Suite("CreditLedger")
struct CreditLedgerTests {

    @Test
    func creditLedger_newLedger_balanceEqualsSpecInitialGrant() {
        let cap = CreditCaps.capFor(.files)

        let ledger = CreditLedger(cap: cap)

        #expect(ledger.balance == cap)
    }

    @Test
    func creditCaps_featureChannels_capEqualsProtocolMax() {
        let featureChannels: [Tandem_V1_Channel] = [
            .notify, .clipboard, .files, .sms, .contacts, .calls, .input, .status
        ]

        for channel in featureChannels {
            #expect(CreditCaps.capFor(channel) == CreditCaps.protocolMax)
        }
    }

    @Test
    func creditLedger_consumeBeyondBalance_returnsInsufficientBalanceUnchanged() {
        var ledger = CreditLedger(cap: 4)

        let result = ledger.consume(5)

        #expect(result == .insufficient)
        #expect(ledger.balance == 4)
    }

    @Test
    func creditLedger_consumeExactBalance_balanceZeroNeverNegative() {
        var ledger = CreditLedger(cap: 4)

        let result = ledger.consume(4)

        #expect(result == .success)
        #expect(ledger.balance == 0)
    }

    @Test
    func creditLedger_grantAboveMax_reportsOverflow() {
        var ledger = CreditLedger(cap: 4)
        ledger.consume(1)

        let result = ledger.applyGrant(4)

        #expect(result == .overflow)
        #expect(ledger.balance == 3)
    }
}
