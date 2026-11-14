import Testing

@testable import TandemApp

@Suite("PeerUnpairedNotice")
@MainActor
struct PeerUnpairedNoticeTests {
    @Test
    func peerUnpairedNotice_namedPeerUnpairs_messageNamesPeer() {
        let notice = PeerUnpairedNotice()

        notice.peerUnpaired(name: "Pixel 9")

        #expect(notice.message == "Pixel 9 unpaired this Mac.")
    }

    @Test
    func peerUnpairedNotice_unnamedPeerUnpairs_messageSaysYourPhone() {
        let notice = PeerUnpairedNotice()

        notice.peerUnpaired(name: nil)

        #expect(notice.message == "Your phone unpaired this Mac.")
    }

    @Test
    func peerUnpairedNotice_cleared_hasNoMessage() {
        let notice = PeerUnpairedNotice()
        notice.peerUnpaired(name: "Pixel 9")

        notice.clear()

        #expect(notice.message == nil)
    }
}
