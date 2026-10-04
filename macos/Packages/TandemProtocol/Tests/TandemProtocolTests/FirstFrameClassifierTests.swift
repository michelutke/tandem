import Foundation
import SwiftProtobuf
import Testing
@testable import TandemProtocol

@Suite("FirstFrameClassifier")
struct FirstFrameClassifierTests {
    @Test
    func classify_versionHelloEnvelope_isEnvelope() throws {
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.versionHello = Tandem_V1_VersionHello()

        #expect(FirstFrameClassifier.classify(body: try envelope.serializedData()) == .envelope)
    }

    @Test
    func classify_mediaHelloWith32ByteTicket_isMediaHelloWithThatTicket() throws {
        var hello = Tandem_V1_MediaHello()
        hello.ticket = Data(repeating: 0xAB, count: 32)

        #expect(
            FirstFrameClassifier.classify(body: try hello.serializedData())
                == .mediaHello(ticket: Data(repeating: 0xAB, count: 32))
        )
    }

    @Test
    func classify_mediaHelloWithoutTicket_isMediaHelloWithNilTicket() throws {
        let body = try Tandem_V1_MediaHello().serializedData()

        #expect(FirstFrameClassifier.classify(body: body) == .mediaHello(ticket: nil))
    }

    @Test
    func classify_undecodableBytes_isMalformed() {
        #expect(FirstFrameClassifier.classify(body: Data([0xFF, 0xFF, 0xFF])) == .malformed)
    }
}
