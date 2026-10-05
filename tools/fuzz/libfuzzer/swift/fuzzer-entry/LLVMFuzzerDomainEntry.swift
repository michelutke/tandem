import FrameEnvelopeFuzzerCore
import Foundation

/// The libFuzzer C entry point for the per-domain message decoder target (E71-13): one generic
/// binary, parametrized by the proto file stem in the `TANDEM_FUZZ_MESSAGE` environment variable
/// (e.g. `media`, `media_control`). Selected by `build_fuzz_target.sh <output> domain`.
nonisolated(unsafe) private var selectedEntry: DomainFuzzEntry?

@_cdecl("LLVMFuzzerInitialize")
public func LLVMFuzzerInitialize(
    _ argc: UnsafeMutablePointer<Int32>?,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>?
) -> Int32 {
    let name = ProcessInfo.processInfo.environment["TANDEM_FUZZ_MESSAGE"] ?? ""
    guard let entry = DomainFuzzRegistry.entry(named: name) else {
        FileHandle.standardError.write(Data("TANDEM_FUZZ_MESSAGE='\(name)' is not a registered proto file stem\n".utf8))
        exit(2)
    }
    selectedEntry = entry
    return 0
}

@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>?, _ size: Int) -> Int32 {
    guard let data, size > 0 else {
        return 0
    }
    selectedEntry?.run(Data(bytes: data, count: size))
    return 0
}
