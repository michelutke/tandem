import CoreGraphics
import Foundation
import TandemProtocol

/// Pure value-type view events (top-left-origin view points, `NSEvent.timestamp` seconds).
public enum MirrorInputEvent: Equatable, Sendable {
    case pressed(point: CGPoint, time: TimeInterval)
    case dragged(point: CGPoint, time: TimeInterval)
    case released(point: CGPoint, time: TimeInterval)
    case scrolled(point: CGPoint, deltaX: Double, deltaY: Double, time: TimeInterval)
    case key(characters: String?, keyCode: UInt16, hasCommandModifiers: Bool)
}

/// Translates view events to `InputEvent`s (E62-07, SPEC § Input events). Points in letterbox bars
/// are never sent; coordinates are stream pixels inside `[0, streamSize)`; emissions are capped at
/// 120/s. Fails closed: nothing is emitted unless the window is key.
public struct MirrorInputMapper: Sendable {
    public static let maxEventsPerSecond = 120.0
    public static let tapSlop: CGFloat = 4
    public static let swipeDurationMs: ClosedRange<Int> = 1...5000

    public var streamSize: CGSize = .zero
    public var windowSize: CGSize = .zero
    public var isWindowKey = false {
        didSet { if !isWindowKey { gesture = nil } }
    }

    private struct Gesture {
        let start: CGPoint
        let startTime: TimeInterval
    }

    private let sessionId: Data
    private var gesture: Gesture?
    private var lastScrollEmit: TimeInterval?
    private var pendingScroll = (dx: 0.0, dy: 0.0)

    public init?(sessionId: Data) {
        guard sessionId.count == 16 else { return nil }
        self.sessionId = sessionId
    }

    public mutating func map(_ event: MirrorInputEvent) -> [Tandem_V1_InputEvent] {
        guard isWindowKey else { return [] }
        switch event {
        case .pressed(let point, let time):
            gesture = contentPixel(point) == nil ? nil : Gesture(start: point, startTime: time)
            return []
        case .dragged:
            return []
        case .released(let point, let time):
            defer { gesture = nil }
            guard let gesture else { return [] }
            return gestureEvent(gesture, end: point, time: time).map { [$0] } ?? []
        case .scrolled(let point, let deltaX, let deltaY, let time):
            return scrollEvent(point: point, deltaX: deltaX, deltaY: deltaY, time: time).map { [$0] } ?? []
        case .key(let characters, let keyCode, let hasCommandModifiers):
            guard let edit = KeyMapper.textEdit(
                characters: characters, keyCode: keyCode, hasCommandModifiers: hasCommandModifiers)
            else { return [] }
            return [makeEvent { $0.event = .textEdit(Self.textEdit(edit)) }]
        }
    }

    private func gestureEvent(_ gesture: Gesture, end: CGPoint, time: TimeInterval) -> Tandem_V1_InputEvent? {
        guard let from = contentPixel(gesture.start) else { return nil }
        let distance = hypot(end.x - gesture.start.x, end.y - gesture.start.y)
        if distance < Self.tapSlop {
            return makeEvent {
                $0.event = .tap(.with { $0.x = from.pixelX; $0.y = from.pixelY })
            }
        }
        guard let target = contentPixel(end, clamped: true) else { return nil }
        let milliseconds = Int(((time - gesture.startTime) * 1000).rounded())
        let duration = min(max(milliseconds, Self.swipeDurationMs.lowerBound), Self.swipeDurationMs.upperBound)
        return makeEvent {
            $0.event = .swipe(.with {
                $0.x1 = from.pixelX; $0.y1 = from.pixelY; $0.x2 = target.pixelX; $0.y2 = target.pixelY
                $0.durationMs = UInt32(duration)
            })
        }
    }

    private mutating func scrollEvent(
        point: CGPoint, deltaX: Double, deltaY: Double, time: TimeInterval
    ) -> Tandem_V1_InputEvent? {
        guard let pixel = contentPixel(point) else { return nil }
        pendingScroll.dx += deltaX
        pendingScroll.dy += deltaY
        if let last = lastScrollEmit, time - last < 1 / Self.maxEventsPerSecond { return nil }
        let deltaX = Self.clampedInt32(pendingScroll.dx)
        let deltaY = Self.clampedInt32(pendingScroll.dy)
        guard deltaX != 0 || deltaY != 0 else { return nil }
        pendingScroll = (0, 0)
        lastScrollEmit = time
        return makeEvent {
            $0.event = .scroll(.with { $0.x = pixel.pixelX; $0.y = pixel.pixelY; $0.dx = deltaX; $0.dy = deltaY })
        }
    }

    private func contentPixel(_ point: CGPoint, clamped: Bool = false) -> (pixelX: UInt32, pixelY: UInt32)? {
        let rect = LetterboxLayout.contentRect(stream: streamSize, window: windowSize)
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard clamped || (point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY)
        else { return nil }
        let pixelX = Self.pixel((point.x - rect.minX) / rect.width, extent: streamSize.width)
        let pixelY = Self.pixel((point.y - rect.minY) / rect.height, extent: streamSize.height)
        return (pixelX, pixelY)
    }

    private static func pixel(_ fraction: CGFloat, extent: CGFloat) -> UInt32 {
        let maxPixel = max(extent.rounded(.down) - 1, 0)
        return UInt32(min(max((fraction * extent).rounded(.down), 0), maxPixel))
    }

    private static func clampedInt32(_ value: Double) -> Int32 {
        Int32(min(max(value.rounded(), Double(Int32.min)), Double(Int32.max)))
    }

    private static func textEdit(_ edit: KeyMapper.Edit) -> Tandem_V1_TextEdit {
        .with {
            switch edit {
            case .insert(let text): $0.edit = .insert(text)
            case .deleteBackward(let count): $0.edit = .deleteBackward(count)
            case .imeEnter: $0.edit = .imeEnter(Tandem_V1_ImeEnter())
            }
        }
    }

    private func makeEvent(_ configure: (inout Tandem_V1_InputEvent) -> Void) -> Tandem_V1_InputEvent {
        .with {
            $0.sessionID = sessionId
            configure(&$0)
        }
    }
}
