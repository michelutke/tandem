import Foundation

/// Adapted from `spikes/e03-01-nwlistener/Sources/nwlistener-spike/Shell.swift` for the
/// `lsof`-based single-listening-socket check (E12-01).
struct ShellError: Error, CustomStringConvertible {
    let command: String
    let status: Int32
    let output: String
    var description: String { "command failed (\(status)): \(command)\n\(output)" }
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw ShellError(
            command: ([launchPath] + arguments).joined(separator: " "),
            status: process.terminationStatus,
            output: output
        )
    }
    return output
}
