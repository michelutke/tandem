import FeatureMirror
import Foundation
import Testing

@Suite struct MirrorPerformanceHarnessTests {
    private func fixtureLuma() throws -> (luma: [UInt8], width: Int, height: Int) {
        let url = try #require(
            Bundle.module.url(forResource: "timestamp-overlay-800x16", withExtension: "pgm", subdirectory: "Fixtures/media")
        )
        let data = [UInt8](try Data(contentsOf: url))
        let newlines = data.indices.filter { data[$0] == UInt8(ascii: "\n") }
        let header = String(decoding: data[0...newlines[2]], as: UTF8.self)
        #expect(header == "P5\n800 16\n255\n")
        return (Array(data[(newlines[2] + 1)...]), 800, 16)
    }

    @Test func timestampOverlayDecoder_fixtureFrame_recoversFrameIndexAndClock() throws {
        let frame = try fixtureLuma()
        let overlay = TimestampOverlayDecoder.decode(luma: frame.luma, width: frame.width, height: frame.height)
        #expect(overlay == TimestampOverlay(frameIndex: 123_456_789, clockMs: 1_700_000_123_456))
    }

    @Test func timestampOverlayDecoder_frameTooSmall_returnsNil() {
        #expect(TimestampOverlayDecoder.decode(luma: [UInt8](repeating: 0, count: 64), width: 8, height: 8) == nil)
    }

    @Test func clockOffsetEstimator_fixtureRoundTrips_withinHalfMinimumRtt() throws {
        let trueOffsetMs: Int64 = 5_000
        let legs: [(sent: Int64, outbound: Int64, inbound: Int64)] = [
            (0, 30, 10), (100, 8, 14), (200, 25, 25), (300, 4, 19)
        ]
        var roundTrips: [ClockRoundTrip] = []
        for leg in legs {
            let arrivedAtPhone = leg.sent + leg.outbound
            roundTrips.append(
                ClockRoundTrip(
                    sentMs: leg.sent,
                    phoneMs: arrivedAtPhone + trueOffsetMs,
                    receivedMs: arrivedAtPhone + leg.inbound
                )
            )
        }
        let minimumRtt = try #require(roundTrips.map { $0.receivedMs - $0.sentMs }.min())
        let estimate = try #require(ClockOffsetEstimator.offsetMs(from: roundTrips))
        #expect(abs(estimate - Double(trueOffsetMs)) <= Double(minimumRtt) / 2)
    }

    @Test func clockOffsetEstimator_noRoundTrips_returnsNil() {
        #expect(ClockOffsetEstimator.offsetMs(from: []) == nil)
    }

    @Test func latencyReport_fixtureSamples_computesFpsAndP95() throws {
        var samples: [FrameSample] = []
        for index in 0..<41 {
            let receivedMs = Int64(index) * 25
            let latencyMs = Int64(60 + index)
            samples.append(FrameSample(phoneClockMs: receivedMs - latencyMs, receivedMs: receivedMs))
        }
        let report = try #require(LatencyReport(samples: samples, phoneMinusMacOffsetMs: 0))
        #expect(report.sustainedFps == 40)
        #expect(report.p95LatencyMs == 98)
    }

    @Test func latencyReport_offsetApplied_shiftsLatency() throws {
        let samples = [FrameSample(phoneClockMs: 5_000, receivedMs: 100), FrameSample(phoneClockMs: 5_050, receivedMs: 150)]
        let report = try #require(LatencyReport(samples: samples, phoneMinusMacOffsetMs: 4_940))
        #expect(report.p95LatencyMs == 40)
    }

    @Test func latencyReport_singleSample_returnsNil() {
        #expect(LatencyReport(samples: [FrameSample(phoneClockMs: 0, receivedMs: 0)], phoneMinusMacOffsetMs: 0) == nil)
    }
}
