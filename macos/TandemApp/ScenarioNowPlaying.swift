#if DEBUG
import FeatureMedia
import SwiftUI
import TandemProtocol

extension ScenarioView {
    /// A phone already playing "Scenario Song" by "Scenario Artist" (E72-08): the title, artist and
    /// transport controls render without a phone.
    @MainActor
    static func makeNowPlayingSeededView() -> some View {
        NowPlayingSeededScenarioView()
    }
}

private struct NowPlayingSeededScenarioView: View {
    @State private var viewModel = NowPlayingViewModel(session: FakeTandemSession())

    var body: some View {
        NowPlayingView(viewModel: viewModel)
            .task {
                var nowPlaying = Tandem_V1_NowPlaying()
                nowPlaying.title = "Scenario Song"
                nowPlaying.artist = "Scenario Artist"
                nowPlaying.state = .playing
                viewModel.handle(nowPlaying)
            }
    }
}
#endif
