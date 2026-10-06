import FeatureMedia
import Testing
@testable import TandemProtocol

@MainActor
@Suite struct NowPlayingViewModelTests {
    private func nowPlaying(title: String = "Song", artist: String = "Band") -> Tandem_V1_NowPlaying {
        var message = Tandem_V1_NowPlaying()
        message.title = title
        message.artist = artist
        message.state = .playing
        return message
    }

    private func commands(_ session: FakeTandemSession) async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await session.sent.filter { $0.channel == .status }.map(\.payload)
    }

    @Test func nowPlayingViewModel_nowPlayingReceived_showsTitleAndArtist() {
        let viewModel = NowPlayingViewModel(session: FakeTandemSession())
        viewModel.handle(nowPlaying())
        #expect(viewModel.title == "Song")
        #expect(viewModel.artist == "Band")
        #expect(viewModel.showsControls)
    }

    @Test func nowPlayingViewModel_nowPlayingFrameOnStatusChannel_showsTitleAndArtist() async {
        let session = FakeTandemSession()
        let viewModel = NowPlayingViewModel(session: session)
        viewModel.start()
        await session.inject(InboundFrame(channel: .status, seq: 1, ack: 0, payload: .nowPlaying(nowPlaying())))
        for _ in 0..<1000 where viewModel.title.isEmpty {
            await Task.yield()
        }
        #expect(viewModel.title == "Song")
    }

    @Test func nowPlayingViewModel_playPauseTapped_sendsOnePlayPauseCommand() async {
        let session = FakeTandemSession()
        let viewModel = NowPlayingViewModel(session: session)
        viewModel.handle(nowPlaying())
        await viewModel.playPause()
        let sent = await commands(session)
        #expect(sent.count == 1)
        guard case .playPause? = sent.first else {
            Issue.record("expected PlayPause, got \(sent)")
            return
        }
    }

    @Test func nowPlayingViewModel_capabilityUnavailable_controlsHidden() {
        let viewModel = NowPlayingViewModel(session: FakeTandemSession())
        viewModel.handle(nowPlaying())
        var unavailable = Tandem_V1_CapabilityUnavailable()
        unavailable.feature = .mediaControl
        viewModel.handle(unavailable)
        #expect(!viewModel.showsControls)
    }
}
