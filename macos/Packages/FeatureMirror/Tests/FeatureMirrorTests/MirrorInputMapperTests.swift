import CoreGraphics
import Foundation
import Testing
import TandemProtocol
@testable import FeatureMirror

private let sessionId = Data(repeating: 7, count: 16)

private func makeMapper(isWindowKey: Bool = true) -> MirrorInputMapper {
    guard var mapper = MirrorInputMapper(sessionId: sessionId) else { fatalError("valid session id") }
    // Stream 1080x2400 in a 1000x1000 window: content rect is x 275..725, y 0..1000.
    mapper.streamSize = CGSize(width: 1080, height: 2400)
    mapper.windowSize = CGSize(width: 1000, height: 1000)
    mapper.isWindowKey = isWindowKey
    return mapper
}

@Test func mirrorInputMapper_invalidSessionIdLength_isNil() {
    #expect(MirrorInputMapper(sessionId: Data(repeating: 1, count: 15)) == nil)
}

@Test func mirrorInputMapper_clickInWindow_emitsTapWithWindowLocalCoordinates() {
    var mapper = makeMapper()
    #expect(mapper.map(.pressed(point: CGPoint(x: 500, y: 500), time: 1.0)).isEmpty)
    let events = mapper.map(.released(point: CGPoint(x: 500, y: 500), time: 1.05))
    #expect(events.count == 1)
    #expect(events[0].sessionID == sessionId)
    #expect(events[0].tap.x == 540)
    #expect(events[0].tap.y == 1200)
}

@Test func mirrorInputMapper_clickInLetterboxBar_emitsNothing() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 100, y: 500), time: 1.0))
    #expect(mapper.map(.released(point: CGPoint(x: 100, y: 500), time: 1.05)).isEmpty)
}

@Test func mirrorInputMapper_clickAtBottomRightEdge_coordinatesStayInsideStream() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 724.9, y: 999.9), time: 1.0))
    let events = mapper.map(.released(point: CGPoint(x: 724.9, y: 999.9), time: 1.01))
    #expect(events.count == 1)
    #expect(events[0].tap.x == 1079)
    #expect(events[0].tap.y == 2399)
}

@Test func mirrorInputMapper_drag300ms_emitsSwipeWithDuration300() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 800), time: 2.0))
    _ = mapper.map(.dragged(point: CGPoint(x: 450, y: 600), time: 2.15))
    let events = mapper.map(.released(point: CGPoint(x: 500, y: 400), time: 2.3))
    #expect(events.count == 1)
    let swipe = events[0].swipe
    #expect(swipe.durationMs == 300)
    #expect(swipe.x1 == UInt32((125.0 / 450.0 * 1080.0).rounded(.down)))
    #expect(swipe.y1 == 1920)
    #expect(swipe.x2 == 540)
    #expect(swipe.y2 == 960)
}

@Test func mirrorInputMapper_dragEndingInLetterbox_endPointClampedInsideStream() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 500), time: 0))
    let events = mapper.map(.released(point: CGPoint(x: 900, y: 500), time: 0.2))
    #expect(events[0].swipe.x2 == 1079)
}

@Test func mirrorInputMapper_dragDurationOutOfRange_clampedTo1And5000() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 800), time: 0))
    #expect(mapper.map(.released(point: CGPoint(x: 500, y: 400), time: 0.0001))[0].swipe.durationMs == 1)
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 800), time: 10))
    #expect(mapper.map(.released(point: CGPoint(x: 500, y: 400), time: 60))[0].swipe.durationMs == 5000)
}

@Test func mirrorInputMapper_scrollWheel_emitsScrollWithEventDeltas() {
    var mapper = makeMapper()
    let events = mapper.map(.scrolled(point: CGPoint(x: 500, y: 500), deltaX: -3, deltaY: 12, time: 5))
    #expect(events.count == 1)
    #expect(events[0].scroll.x == 540)
    #expect(events[0].scroll.y == 1200)
    #expect(events[0].scroll.dx == -3)
    #expect(events[0].scroll.dy == 12)
}

@Test func mirrorInputMapper_scrollInLetterboxBar_emitsNothing() {
    var mapper = makeMapper()
    #expect(mapper.map(.scrolled(point: CGPoint(x: 50, y: 500), deltaX: 0, deltaY: 5, time: 5)).isEmpty)
}

@Test func mirrorInputMapper_windowNotKey_emitsNoEvent() {
    var mapper = makeMapper(isWindowKey: false)
    _ = mapper.map(.pressed(point: CGPoint(x: 500, y: 500), time: 1))
    #expect(mapper.map(.released(point: CGPoint(x: 500, y: 500), time: 1.05)).isEmpty)
    #expect(mapper.map(.scrolled(point: CGPoint(x: 500, y: 500), deltaX: 0, deltaY: 5, time: 2)).isEmpty)
    #expect(mapper.map(.key(characters: "a", keyCode: 0, hasCommandModifiers: false)).isEmpty)
}

@Test func mirrorInputMapper_windowResignsKeyMidDrag_noSwipeEmitted() {
    var mapper = makeMapper()
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 800), time: 0))
    mapper.isWindowKey = false
    mapper.isWindowKey = true
    #expect(mapper.map(.released(point: CGPoint(x: 500, y: 400), time: 0.3)).isEmpty)
}

@Test func mirrorInputMapper_rapidDrag_coalescedToAtMost120EventsPerSecond() {
    var mapper = makeMapper()
    var emitted = 0
    _ = mapper.map(.pressed(point: CGPoint(x: 400, y: 800), time: 0))
    for index in 1...1000 {
        let point = CGPoint(x: 400 + Double(index) / 20, y: 800 - Double(index) / 10)
        emitted += mapper.map(.dragged(point: point, time: Double(index) / 1000)).count
    }
    emitted += mapper.map(.released(point: CGPoint(x: 450, y: 700), time: 1.0)).count
    #expect(emitted <= 120)
}

@Test func mirrorInputMapper_rapidScroll_coalescedToAtMost120PerSecond() {
    var mapper = makeMapper()
    var count = 0
    var totalDy: Int32 = 0
    for index in 0..<1000 {
        let events = mapper.map(.scrolled(point: CGPoint(x: 500, y: 500), deltaX: 0, deltaY: 1, time: Double(index) / 1000))
        count += events.count
        totalDy += events.reduce(0) { $0 + $1.scroll.dy }
    }
    #expect(count <= 120)
    #expect(totalDy >= 990)
}

@Test func mirrorInputMapper_keyEvent_emitsTextEditBoundToSession() {
    var mapper = makeMapper()
    let events = mapper.map(.key(characters: "a", keyCode: 0, hasCommandModifiers: false))
    #expect(events.count == 1)
    #expect(events[0].sessionID == sessionId)
    #expect(events[0].textEdit.insert == "a")
}

@Test func keyMapper_lettersBackspaceEnter_mapToTextEditOps() {
    #expect(KeyMapper.textEdit(characters: "a", keyCode: 0, hasCommandModifiers: false) == .insert("a"))
    #expect(KeyMapper.textEdit(characters: "Ä", keyCode: 39, hasCommandModifiers: false) == .insert("Ä"))
    #expect(KeyMapper.textEdit(characters: "\u{7F}", keyCode: 51, hasCommandModifiers: false) == .deleteBackward(1))
    #expect(KeyMapper.textEdit(characters: "\r", keyCode: 36, hasCommandModifiers: false) == .imeEnter)
    #expect(KeyMapper.textEdit(characters: "\u{3}", keyCode: 76, hasCommandModifiers: false) == .imeEnter)
}

@Test func keyMapper_nonTextKeys_mapToNothing() {
    #expect(KeyMapper.textEdit(characters: "\u{F700}", keyCode: 126, hasCommandModifiers: false) == nil)
    #expect(KeyMapper.textEdit(characters: "\t", keyCode: 48, hasCommandModifiers: false) == nil)
    #expect(KeyMapper.textEdit(characters: "c", keyCode: 8, hasCommandModifiers: true) == nil)
    #expect(KeyMapper.textEdit(characters: nil, keyCode: 0, hasCommandModifiers: false) == nil)
    #expect(KeyMapper.textEdit(characters: "", keyCode: 0, hasCommandModifiers: false) == nil)
}

@Test func keyMapper_longInsert_truncatedTo4096CodePoints() {
    let long = String(repeating: "x", count: 5000)
    guard case .insert(let text) = KeyMapper.textEdit(characters: long, keyCode: 0, hasCommandModifiers: false) else {
        Issue.record("expected insert")
        return
    }
    #expect(text.unicodeScalars.count == 4096)
}
