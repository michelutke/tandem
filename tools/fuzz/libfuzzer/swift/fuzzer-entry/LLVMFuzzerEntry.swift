import FrameEnvelopeFuzzerCore
import Foundation

/// The libFuzzer C entry point (E15-14). This file lives outside `swift/Sources/`, so it is
/// never part of any SwiftPM target `swift build`/`swift test` compiles — `swift test` (used by
/// `macos/test-packages.sh` and CI, on any toolchain) never needs the libFuzzer runtime. Only
/// `build_fuzz_target.sh` compiles it, with a direct `swiftc -sanitize=fuzzer,address
/// -parse-as-library` invocation against the already-built `FrameEnvelopeFuzzerCore` module: with
/// `-parse-as-library` and no top-level statements, this file declares no `main`, so the linker
/// resolves `main` from libFuzzer's own runtime instead (the standard shape of a Swift libFuzzer
/// harness; see README.md for why this can't be an ordinary SwiftPM executable target).
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32 {
    guard let data, size > 0 else {
        fuzzOne(Data())
        return 0
    }
    fuzzOne(Data(bytes: data, count: size))
    return 0
}
