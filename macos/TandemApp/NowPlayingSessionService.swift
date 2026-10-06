import FeatureMedia
import Observation
import SwiftUI
import TandemCrypto
import TandemProtocol
import TandemTransport

/// The attached session's ``NowPlayingViewModel``, if any, so the menu bar's now-playing section
/// observes one stable object across reconnects.
@MainActor
@Observable
final class ActiveNowPlaying {
    private(set) var viewModel: NowPlayingViewModel?

    nonisolated init() {}

    func set(_ viewModel: NowPlayingViewModel?) {
        self.viewModel = viewModel
    }
}

/// Media control for the attached session: a ``NowPlayingViewModel`` observing STATUS through
/// ``TandemSession/receive(_:)``.
final class NowPlayingSessionService: SessionService, @unchecked Sendable {
    private let active: ActiveNowPlaying

    init(active: ActiveNowPlaying) {
        self.active = active
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let active = active
        await MainActor.run {
            let viewModel = NowPlayingViewModel(session: session)
            viewModel.start()
            active.set(viewModel)
        }
    }

    func detach(peer: SpkiFingerprint) async {
        let active = active
        await MainActor.run { active.set(nil) }
    }
}

/// ``NowPlayingView`` over whichever session's media control is attached.
struct ActiveNowPlayingView: View {
    let activeNowPlaying: ActiveNowPlaying

    var body: some View {
        if let viewModel = activeNowPlaying.viewModel {
            NowPlayingView(viewModel: viewModel)
        }
    }
}
