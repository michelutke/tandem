import Foundation
import Network
import Security

setbuf(stdout, nil)

struct Args {
    let positional: [String]
    let flags: [String: String]
    let switches: Set<String>

    init(_ raw: [String]) {
        var positional: [String] = []
        var flags: [String: String] = [:]
        var switches: Set<String> = []
        var i = 0
        while i < raw.count {
            let token = raw[i]
            if token.hasPrefix("--") {
                let name = String(token.dropFirst(2))
                if i + 1 < raw.count, !raw[i + 1].hasPrefix("--") {
                    flags[name] = raw[i + 1]
                    i += 2
                } else {
                    switches.insert(name)
                    i += 1
                }
            } else {
                positional.append(token)
                i += 1
            }
        }
        self.positional = positional
        self.flags = flags
        self.switches = switches
    }

    func value(_ name: String, default def: String) -> String { flags[name] ?? def }
    func value(_ name: String) -> String? { flags[name] }
    func flag(_ name: String) -> Bool { switches.contains(name) }
}

func backing(from args: Args) -> Bool {
    args.value("backing", default: "se") == "se"
}

/// `--legacy-keychain` never means "the login keychain" in this spike -- it means "a fresh
/// temporary keychain file this process creates under `--keychain-dir` and the caller is
/// responsible for deleting via `TemporaryKeychain.cleanup()`". This spike must never write
/// keychain items to the user's login keychain.
func makeTemporaryKeychainIfNeeded(_ args: Args) throws -> TemporaryKeychain? {
    guard args.flag("legacy-keychain") else { return nil }
    let dir = URL(fileURLWithPath: args.value("keychain-dir", default: "/tmp/se-identity-spike-\(UUID().uuidString)"))
    return try TemporaryKeychain(directory: dir, password: args.value("keychain-password", default: UUID().uuidString), create: true)
}

func cmdKeygen(_ args: Args) throws {
    let label = args.value("label", default: "se-spike-identity")
    let secureEnclave = backing(from: args)
    let persistent = args.value("persistent", default: "true") == "true"
    let keep = args.flag("keep")
    let tempKeychain = try makeTemporaryKeychainIfNeeded(args)
    var cleanupTempOnExit = tempKeychain != nil && !keep
    defer { if cleanupTempOnExit { tempKeychain?.cleanup() } }
    let identity = try generateIdentity(
        label: label, secureEnclave: secureEnclave, persistent: persistent,
        dataProtectionKeychain: tempKeychain == nil, temporaryKeychain: tempKeychain
    )
    print("keygen: label=\(label) backing=\(identity.backing) persistent=\(persistent) data_protection_keychain=\(tempKeychain == nil) spki_sha256=\(hex(identity.spkiSha256))")
    if let tempKeychain {
        if keep {
            print("keygen: temp keychain KEPT at path=\(tempKeychain.url.path) -- caller must delete it (e.g. via relaunch-check's paired run, then `rm -rf`)")
            cleanupTempOnExit = false
        }
    } else if !keep {
        cleanupIdentity(label: label)
    }
}

func cmdExportTest(_ args: Args) throws {
    let label = args.value("label", default: "se-spike-export-test")
    let secureEnclave = backing(from: args)
    let tempKeychain = try makeTemporaryKeychainIfNeeded(args)
    defer { tempKeychain?.cleanup() }
    let identity = try generateIdentity(
        label: label, secureEnclave: secureEnclave, persistent: false,
        dataProtectionKeychain: tempKeychain == nil, temporaryKeychain: tempKeychain
    )
    let (data, error) = attemptPrivateKeyExport(identity.privateKey)
    if let data {
        print("export-test: backing=\(identity.backing) EXPORT SUCCEEDED bytes=\(data.count) (unexpected for secureEnclave)")
    } else {
        print("export-test: backing=\(identity.backing) export failed as expected: \(error ?? "nil")")
    }
    if tempKeychain == nil {
        cleanupIdentity(label: label)
    }
}

func cmdRelaunchCheck(_ args: Args) throws {
    let label = args.value("label", default: "se-spike-identity")
    if let keychainDir = args.value("keychain-dir"), let password = args.value("keychain-password") {
        guard let (identity, kc) = try loadPersistentIdentity(
            fromTemporaryKeychainAt: URL(fileURLWithPath: keychainDir), password: password, label: label
        ) else {
            print("relaunch-check: label=\(label) NOT FOUND (temporary keychain at \(keychainDir))")
            return
        }
        print("relaunch-check: label=\(label) backing=\(identity.backing) spki_sha256=\(hex(identity.spkiSha256)) (reopened temporary keychain at \(keychainDir))")
        kc.disown() // do not delete here -- caller owns cleanup of the original TemporaryKeychain
        return
    }
    guard let identity = try loadPersistentIdentity(label: label) else {
        print("relaunch-check: label=\(label) NOT FOUND (data-protection keychain)")
        return
    }
    print("relaunch-check: label=\(label) backing=\(identity.backing) spki_sha256=\(hex(identity.spkiSha256))")
}

func cmdCleanup(_ args: Args) {
    let label = args.value("label", default: "se-spike-identity")
    cleanupIdentity(label: label)
    print("cleanup: removed data-protection-keychain items for label=\(label) (temporary keychains are cleaned up by whichever command created them)")
}

func cmdListen(_ args: Args) throws {
    let label = args.value("label", default: "se-spike-identity")
    let secureEnclave = backing(from: args)
    let port = UInt16(args.value("port", default: "4443"))!
    let exitAfter = Int(args.value("exit-after", default: "20"))!
    let tempKeychain = try makeTemporaryKeychainIfNeeded(args)
    defer { tempKeychain?.cleanup() }

    let identity = try generateIdentity(
        label: label, secureEnclave: secureEnclave, persistent: true,
        dataProtectionKeychain: tempKeychain == nil, temporaryKeychain: tempKeychain
    )
    print("listen: generated identity label=\(label) backing=\(identity.backing) spki_sha256=\(hex(identity.spkiSha256))")

    var readyCount = 0
    var failedCount = 0
    let listener = try SpikeListener(
        port: port,
        identity: identity,
        log: { print($0) },
        onReady: { elapsedMs in
            readyCount += 1
            print("RESULT backing=\(identity.backing) run=\(readyCount) elapsed_ms=\(elapsedMs)")
            if readyCount + failedCount >= exitAfter {
                if tempKeychain == nil { cleanupIdentity(label: label) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            }
        },
        onFailed: { _ in
            failedCount += 1
            if readyCount + failedCount >= exitAfter {
                if tempKeychain == nil { cleanupIdentity(label: label) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            }
        }
    )
    print("listen: starting on 127.0.0.1:\(port) backing=\(identity.backing) exit_after=\(exitAfter)")
    listener.start(log: { print($0) })
    RunLoop.main.run()
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first else {
    print("usage: se-identity-spike <keygen|export-test|relaunch-check|cleanup|listen> [--flag value ...]")
    exit(64)
}
let args = Args(Array(arguments.dropFirst()))

do {
    switch subcommand {
    case "keygen": try cmdKeygen(args)
    case "export-test": try cmdExportTest(args)
    case "relaunch-check": try cmdRelaunchCheck(args)
    case "cleanup": cmdCleanup(args)
    case "listen": try cmdListen(args)
    default:
        print("unknown subcommand: \(subcommand)")
        exit(64)
    }
} catch {
    print("ERROR: \(error)")
    exit(1)
}
