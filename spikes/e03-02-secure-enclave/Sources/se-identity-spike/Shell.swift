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

/// Generates a throwaway P-256 client key + self-signed cert on disk via openssl, purely to
/// hand to `openssl s_client -cert/-key` as the mTLS client identity. This never touches the
/// keychain -- it is the peer side, not the thing under test.
func generateOpenSSLClientIdentity(workDir: URL) throws -> (certPath: URL, keyPath: URL) {
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    let keyPath = workDir.appendingPathComponent("client-key.pem")
    let certPath = workDir.appendingPathComponent("client-cert.pem")
    _ = try runOpenSSL(["ecparam", "-genkey", "-name", "prime256v1", "-noout", "-out", keyPath.path])
    _ = try runOpenSSL([
        "req", "-new", "-x509", "-key", keyPath.path, "-out", certPath.path,
        "-days", "2", "-subj", "/CN=se-spike-openssl-client", "-sha256"
    ])
    return (certPath, keyPath)
}
