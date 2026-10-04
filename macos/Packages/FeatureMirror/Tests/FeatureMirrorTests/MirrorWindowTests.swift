import CoreGraphics
import Testing
import TandemProtocol
@testable import FeatureMirror

@Test func letterboxLayout_portraitStreamInSquareWindow_contentRect450x1000AtX275() {
    let rect = LetterboxLayout.contentRect(
        stream: CGSize(width: 1080, height: 2400), window: CGSize(width: 1000, height: 1000))
    #expect(rect == CGRect(x: 275, y: 0, width: 450, height: 1000))
}

@Test func letterboxLayout_landscapeStreamInSquareWindow_contentRect1000x450AtY275() {
    let rect = LetterboxLayout.contentRect(
        stream: CGSize(width: 2400, height: 1080), window: CGSize(width: 1000, height: 1000))
    #expect(rect == CGRect(x: 0, y: 275, width: 1000, height: 450))
}

@Test func letterboxLayout_invalidSize_returnsZeroRect() {
    #expect(LetterboxLayout.contentRect(stream: .zero, window: CGSize(width: 10, height: 10)) == .zero)
    #expect(LetterboxLayout.contentRect(stream: CGSize(width: 10, height: 10), window: .zero) == .zero)
}

@MainActor
@Test func mirrorWindowModel_rotationChanged_recomputesContentRectForSwappedAspect() {
    let model = MirrorWindowModel(
        streamSize: CGSize(width: 1080, height: 2400), windowSize: CGSize(width: 1000, height: 1000))
    #expect(model.contentRect == CGRect(x: 275, y: 0, width: 450, height: 1000))
    model.rotationChanged(.landscape)
    #expect(model.streamSize == CGSize(width: 2400, height: 1080))
    #expect(model.contentRect == CGRect(x: 0, y: 275, width: 1000, height: 450))
    model.rotationChanged(.reverseLandscape)
    #expect(model.streamSize == CGSize(width: 2400, height: 1080))
}

@MainActor
@Test func mirrorWindowModel_windowResized_recomputesContentRect() {
    let model = MirrorWindowModel(
        streamSize: CGSize(width: 1080, height: 2400), windowSize: CGSize(width: 1000, height: 1000))
    model.windowResized(CGSize(width: 450, height: 1000))
    #expect(model.contentRect == CGRect(x: 0, y: 0, width: 450, height: 1000))
}

@MainActor
@Test func mirrorWindowModel_mediaFormat_updatesStreamSize() {
    let model = MirrorWindowModel(streamSize: .zero, windowSize: CGSize(width: 1000, height: 1000))
    model.mediaFormatChanged(width: 1080, height: 2400)
    #expect(model.contentRect == CGRect(x: 275, y: 0, width: 450, height: 1000))
}
