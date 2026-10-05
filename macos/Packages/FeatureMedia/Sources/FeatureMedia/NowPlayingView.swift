import SwiftUI
import TandemDesign

/// Now-playing display with transport controls (E72-08, ui-spec Main window). Hidden entirely
/// until a `NowPlaying` arrives and whenever the phone reports media control unavailable.
public struct NowPlayingView: View {
    private let viewModel: NowPlayingViewModel

    public init(viewModel: NowPlayingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            if viewModel.showsControls {
                Text(viewModel.title)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
                    .accessibilityIdentifier("nowPlayingTitle")
                Text(viewModel.artist)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier("nowPlayingArtist")
                HStack(spacing: TandemSpacing.small) {
                    PillButton("Previous", kind: .secondary) { Task { await viewModel.previous() } }
                        .accessibilityIdentifier("nowPlayingPrevious")
                    PillButton(viewModel.isPlaying ? "Pause" : "Play") { Task { await viewModel.playPause() } }
                        .accessibilityIdentifier("nowPlayingPlayPause")
                    PillButton("Next", kind: .secondary) { Task { await viewModel.next() } }
                        .accessibilityIdentifier("nowPlayingNext")
                }
            }
        }
        .task { viewModel.start() }
    }
}
