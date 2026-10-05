import Foundation
import Observation
import TandemProtocol

/// Mac side of media control (E72-08, PRD F-10.1). A received `NowPlaying` shows its title and
/// artist; play/pause/next/previous send one command each on STATUS. `CapabilityUnavailable`
/// hides the controls. Title and artist are untrusted peer input and pass
/// ``DisplayStringSanitizer`` before presentation; neither is ever logged (invariant 7).
@MainActor
@Observable
public final class NowPlayingViewModel {
    public private(set) var title = ""
    public private(set) var artist = ""
    public private(set) var isPlaying = false
    public private(set) var isCapabilityUnavailable = false
    public private(set) var hasNowPlaying = false

    public var showsControls: Bool { hasNowPlaying && !isCapabilityUnavailable }

    private let session: any TandemSession

    @ObservationIgnored
    private nonisolated(unsafe) var statusTask: Task<Void, Never>?

    public init(session: any TandemSession) {
        self.session = session
    }

    deinit {
        statusTask?.cancel()
    }

    public func start() {
        statusTask?.cancel()
        let session = session
        statusTask = Task { [weak self] in
            for await frame in await session.receive(.status) {
                switch frame.payload {
                case .nowPlaying(let nowPlaying)?: self?.handle(nowPlaying)
                case .capabilityUnavailable(let unavailable)?: self?.handle(unavailable)
                default: continue
                }
            }
        }
    }

    public func handle(_ nowPlaying: Tandem_V1_NowPlaying) {
        title = DisplayStringSanitizer.sanitize(Data(nowPlaying.title.utf8), kind: .title)
        artist = DisplayStringSanitizer.sanitize(Data(nowPlaying.artist.utf8), kind: .name)
        isPlaying = nowPlaying.state == .playing
        hasNowPlaying = true
    }

    public func handle(_ unavailable: Tandem_V1_CapabilityUnavailable) {
        guard unavailable.feature == .mediaControl else { return }
        isCapabilityUnavailable = true
    }

    public func playPause() async {
        try? await session.send(.status, payload: .playPause(Tandem_V1_PlayPause()))
    }

    public func next() async {
        try? await session.send(.status, payload: .next(Tandem_V1_Next()))
    }

    public func previous() async {
        try? await session.send(.status, payload: .previous(Tandem_V1_Previous()))
    }
}
