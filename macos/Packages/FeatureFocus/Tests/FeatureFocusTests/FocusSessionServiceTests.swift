import FeatureFocus
import Foundation
import Testing
@testable import TandemCrypto
@testable import TandemProtocol

@Suite struct FocusSessionServiceTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 1, count: 32))
    // swiftlint:disable:next force_try
    private let otherPeer = try! SpkiFingerprint(bytes: Data(repeating: 2, count: 32))

    private func focusStates(_ session: FakeTandemSession) async -> [Bool] {
        await session.sent.compactMap { frame in
            guard frame.channel == .control, case .focusState(let state) = frame.payload else { return nil }
            return state.on
        }
    }

    private func settle(_ condition: () async -> Bool) async {
        for _ in 0..<1000 where !(await condition()) {
            await Task.yield()
        }
        #expect(await condition())
    }

    private func drain() async {
        for _ in 0..<200 {
            await Task.yield()
        }
    }

    @Test func focusSessionService_attach_sendsFocusChangesOnThatSession() async {
        let source = RecordingFocusStateSource()
        let service = FocusSessionService(makeSource: { source })
        let session = FakeTandemSession()
        await service.attach(peer: peer, session: session)
        source.emit(true)
        await settle { await focusStates(session) == [true] }
        await service.detach(peer: peer)
    }

    @Test func focusSessionService_twoSessions_eachGetsItsOwnSource() async {
        let sources = [RecordingFocusStateSource(), RecordingFocusStateSource()]
        let next = Counter()
        let service = FocusSessionService(makeSource: { sources[next.increment()] })
        let first = FakeTandemSession()
        let second = FakeTandemSession()
        await service.attach(peer: peer, session: first)
        await service.attach(peer: otherPeer, session: second)
        sources[1].emit(true)
        await settle { await focusStates(second) == [true] }
        await drain()
        #expect(await focusStates(first).isEmpty)
        await service.detach(peer: peer)
        await service.detach(peer: otherPeer)
    }

    @Test func focusSessionService_detach_stopsSending() async {
        let source = RecordingFocusStateSource()
        let service = FocusSessionService(makeSource: { source })
        let session = FakeTandemSession()
        await service.attach(peer: peer, session: session)
        await service.detach(peer: peer)
        source.emit(true)
        await drain()
        #expect(await focusStates(session).isEmpty)
    }

    @Test func focusSessionService_reattachSamePeer_replacesPreviousSender() async {
        let sources = [RecordingFocusStateSource(), RecordingFocusStateSource()]
        let next = Counter()
        let service = FocusSessionService(makeSource: { sources[next.increment()] })
        let old = FakeTandemSession()
        let replacement = FakeTandemSession()
        await service.attach(peer: peer, session: old)
        await service.attach(peer: peer, session: replacement)
        sources[0].emit(true)
        sources[1].emit(true)
        await settle { await focusStates(replacement) == [true] }
        await drain()
        #expect(await focusStates(old).isEmpty)
        await service.detach(peer: peer)
    }
}
