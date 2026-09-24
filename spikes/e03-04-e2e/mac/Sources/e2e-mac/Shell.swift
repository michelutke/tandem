import Foundation

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
        throw ShellError(command: ([launchPath] + arguments).joined(separator: " "), status: process.terminationStatus, output: output)
    }
    return output
}

func runOpenSSL(_ arguments: [String]) throws -> String {
    let candidates = [ProcessInfo.processInfo.environment["OPENSSL_BIN"], "/opt/homebrew/bin/openssl", "/usr/local/bin/openssl", "/usr/bin/openssl"].compactMap { $0 }
    let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/openssl"
    return try run(path, arguments)
}

func runSecurity(_ arguments: [String]) throws -> String {
    try run("/usr/bin/security", arguments)
}
