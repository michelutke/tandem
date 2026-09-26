import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E12-12 (D-67): compile-time and reflection checks over ``TandemSession`` itself, as opposed to
/// a specific conformer's behavior (``ByteStreamSessionTests``, ``FakeTandemSessionTests``).
@Suite("TandemSession protocol")
struct TandemSessionProtocolTests {
    /// This whole file -- and every other file in `TandemProtocolTests` -- compiles and runs
    /// against every ``TandemSession`` requirement (`send`, `receive`, `state`, `close`) without
    /// this target ever importing `Network`, proving the protocol names no `Network` framework
    /// type (acceptance: "No public requirement of the TandemSession protocol mentions a Network
    /// framework type").
    @Test
    func tandemSessionProtocol_testTargetWithoutNetworkImport_compilesAgainstIt() async throws {
        let session: TandemSession = FakeTandemSession()

        _ = session.state
        try await session.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        _ = await session.receive(.notify)
        await session.close()
    }

    /// Reflects over both a ``ByteStreamSession`` and a ``FakeTandemSession`` and asserts none of
    /// their members -- which must exist to satisfy every ``TandemSession`` requirement plus
    /// whatever each conformer stores to do so -- is named or typed as a channel-binding/exporter
    /// value (D-67: channel binding is not a transport concern).
    @Test
    func tandemSessionProtocol_publicRequirements_noChannelBindingOrExporterMember() async {
        let forbiddenSubstrings = ["channelbinding", "exporter", "exportkeyingmaterial"]

        let pair = InMemoryConnectionPair()
        let byteStreamSession = ByteStreamSession(
            multiplexer: ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send),
            stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )
        let fakeSession = FakeTandemSession()

        for instance in [Mirror(reflecting: byteStreamSession), Mirror(reflecting: fakeSession)] {
            for child in instance.children {
                guard let label = child.label else { continue }
                let lowered = label.lowercased()
                for forbidden in forbiddenSubstrings {
                    #expect(
                        !lowered.contains(forbidden),
                        "\(label) looks like a channel-binding/exporter member"
                    )
                }
            }
        }
    }
}
