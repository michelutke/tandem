import FrameEnvelopeFuzzerCore
import Foundation

/// The libFuzzer C entry point for the Envelope decoder target (E71-02); same shape and build
/// rules as `LLVMFuzzerEntry.swift`, selected by `build_fuzz_target.sh <output> envelope`.
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32 {
    guard let data, size > 0 else {
        return 0
    }
    fuzzOneEnvelope(Data(bytes: data, count: size))
    return 0
}
