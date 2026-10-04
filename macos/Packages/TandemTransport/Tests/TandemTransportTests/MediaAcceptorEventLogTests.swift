import Foundation
import Testing
@testable import TandemTransport

@Suite("MediaAcceptorEvent log description")
struct MediaAcceptorEventLogTests {
    @Test
    func logDescription_ticketRejected_namesOnlyTheReason() {
        #expect(MediaAcceptorEvent.ticketRejected(.consumed).logDescription == "ticketRejected(consumed)")
        #expect(MediaAcceptorEvent.ticketRejected(.revoked).logDescription == "ticketRejected(revoked)")
        #expect(MediaAcceptorEvent.ticketRejected(.peerMismatch).logDescription == "ticketRejected(peerMismatch)")
    }

    @Test
    func logDescription_boundAndClosed_omitSessionIdentifier() {
        #expect(MediaAcceptorEvent.bound(UUID()).logDescription == "bound")
        #expect(MediaAcceptorEvent.closed(.protocolTimeout).logDescription == "closed(protocolTimeout)")
    }
}
