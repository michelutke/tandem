import Foundation
import Testing
@testable import FrameEnvelopeFuzzerCore

/// E71-13: replays hand-built inputs through every registry entry on a plain `swift test`.
struct DomainFuzzRegistryTests {
    private static let inputs: [Data] = [
        Data(),
        Data([0x00]),
        Data([0x0A, 0x00]),
        Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]),
        Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]),
        Data(repeating: 0xAB, count: 4096)
    ]

    @Test
    func registry_everyEntryOnMalformedInputs_doesNotCrash() {
        #expect(DomainFuzzRegistry.entries.count == 18)
        for entry in DomainFuzzRegistry.entries {
            for input in Self.inputs {
                entry.run(input)
            }
        }
    }

    @Test
    func registry_entryNamedByProtoStem_resolves() {
        #expect(DomainFuzzRegistry.entry(named: "media_control")?.file == "media_control.proto")
        #expect(DomainFuzzRegistry.entry(named: "nope") == nil)
    }

    @Test
    func fuzzFragmentSequence_completeThreeFragmentUnit_doesNotCrash() {
        var input = Data()
        for index in 0..<3 {
            input += [7, UInt8(index), 3, 2, 0xAA, 0xBB]
        }
        fuzzFragmentSequence(input)
    }

    @Test
    func fuzzFragmentSequence_violationsAndTruncation_doNotCrash() {
        fuzzFragmentSequence(Data([1, 1, 3, 2, 0xAA]))
        fuzzFragmentSequence(Data([1, 0, 9, 0, 1, 0, 3, 255]))
        fuzzFragmentSequence(Data([1, 0, 2, 1, 0xAA, 2, 1, 2, 1, 0xBB]))
    }
}
