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

func cmdSetup(_ args: Args) throws {
    let workdir = args.value("workdir", default: "/tmp/nwlistener-spike")
    let dir = URL(fileURLWithPath: workdir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    for name in ["server", "good-client", "attacker-client"] {
        let genDir = dir.appendingPathComponent("gen-\(name)")
        let (p12, pass) = try generateSelfSignedP256Identity(commonName: "tandem-spike-\(name)", workDir: genDir)
        try p12.write(to: dir.appendingPathComponent("\(name).p12"))
        try pass.write(to: dir.appendingPathComponent("\(name).pass"), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: genDir)

        let kc = try TemporaryKeychain()
        let identity = try kc.importPKCS12(data: p12, passphrase: pass)
        let fp = try spkiFingerprint(for: identity.certificate)
        try hex(fp).write(to: dir.appendingPathComponent("\(name).fingerprint"), atomically: true, encoding: .utf8)
        kc.cleanup()
        print("setup: \(name) spki_sha256=\(hex(fp))")
    }
    print("setup: complete workdir=\(dir.path)")
}

func loadIdentity(workdir: String, name: String) throws -> GeneratedIdentity {
    let dir = URL(fileURLWithPath: workdir)
    let p12 = try Data(contentsOf: dir.appendingPathComponent("\(name).p12"))
    let pass = try String(contentsOf: dir.appendingPathComponent("\(name).pass"), encoding: .utf8)
    let kc = try TemporaryKeychain()
    // Intentionally leaked for process lifetime: the identity's SecIdentity must stay valid for
    // as long as Network.framework holds onto it. Cleaned up implicitly by macOS deleting
    // /tmp on reboot; each `swift run` invocation gets its own fresh temp keychain.
    return try kc.importPKCS12(data: p12, passphrase: pass)
}

func loadFingerprint(workdir: String, name: String) throws -> Data {
    let dir = URL(fileURLWithPath: workdir)
    let hexString = try String(contentsOf: dir.appendingPathComponent("\(name).fingerprint"), encoding: .utf8)
    guard let data = dataFromHex(hexString) else {
        throw NSError(domain: "nwlistener-spike", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad fingerprint file for \(name)"])
    }
    return data
}

func cmdListen(_ args: Args) throws {
    let workdir = args.value("workdir", default: "/tmp/nwlistener-spike")
    let port = UInt16(args.value("port", default: "4443"))!
    let acceptUnpinned = args.flag("accept-unpinned")
    let ticketMode: TicketMode = args.value("tickets", default: "disabled") == "enabled" ? .enabled : .disabled
    let resumptionEnabled = args.value("resumption", default: "disabled") == "enabled"
    let noAlpn = args.flag("no-alpn")
    let deadline = Double(args.value("handshake-deadline", default: "10")) ?? 10
    let exitAfter = args.value("exit-after").flatMap { Int($0) }

    let identity = try loadIdentity(workdir: workdir, name: "server")
    print("listen: server spki_sha256=\(hex(try spkiFingerprint(for: identity.certificate)))")

    let pin: PinPolicy
    if acceptUnpinned {
        pin = PinPolicy(expectedFingerprint: Data(count: 32), acceptAnyClient: true)
    } else {
        let expected = try loadFingerprint(workdir: workdir, name: "good-client")
        pin = PinPolicy(expectedFingerprint: expected, acceptAnyClient: false)
    }

    let options = makeTLSOptions(
        localIdentity: identity.secIdentity,
        peerAuthenticationRequired: true,
        alpn: noAlpn ? .none : .require("tandem/1"),
        pin: pin,
        ticketMode: ticketMode,
        resumptionEnabled: resumptionEnabled,
        log: { print("LOG[listener] \($0)") }
    )

    let listener = try SpikeListener(port: port, options: options, handshakeDeadline: deadline, exitAfter: exitAfter)
    print("listen: starting on 127.0.0.1:\(port) tickets=\(ticketMode) resumption=\(resumptionEnabled) alpn=\(noAlpn ? "none" : "tandem/1") accept_unpinned=\(acceptUnpinned)")
    listener.start()
    RunLoop.main.run()
}

func cmdClient(_ args: Args) throws {
    let workdir = args.value("workdir", default: "/tmp/nwlistener-spike")
    let host = args.value("host", default: "127.0.0.1")
    let port = UInt16(args.value("port", default: "4443"))!
    let identityName = args.value("identity", default: "good-client") // good-client | attacker-client | none
    let alpnArg = args.value("alpn", default: "tandem/1") // tandem/1 | none | any other string
    let ticketMode: TicketMode = args.value("tickets", default: "disabled") == "enabled" ? .enabled : .disabled
    let resumptionEnabled = args.value("resumption", default: "disabled") == "enabled"
    let maxVersion: tls_protocol_version_t? = args.value("max-tls-version") == "v12" ? .TLSv12 : nil
    let timeout = Double(args.value("timeout", default: "8")) ?? 8
    let pinServer = !args.flag("no-server-pin")

    var pin: PinPolicy? = nil
    if pinServer {
        let expected = try loadFingerprint(workdir: workdir, name: "server")
        pin = PinPolicy(expectedFingerprint: expected, acceptAnyClient: false)
    }

    let alpnMode: AlpnMode = alpnArg == "none" ? .none : .require(alpnArg)

    let options: NWProtocolTLS.Options
    if identityName == "none" {
        // No client certificate at all: build options without setting a local identity.
        options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, maxVersion ?? .TLSv13)
        if case .require(let proto) = alpnMode {
            sec_protocol_options_add_tls_application_protocol(sec, proto)
        }
        sec_protocol_options_set_tls_tickets_enabled(sec, ticketMode == .enabled)
        sec_protocol_options_set_tls_resumption_enabled(sec, resumptionEnabled)
        if let pin {
            let log: (String) -> Void = { print("LOG[client] \($0)") }
            let queue = DispatchQueue(label: "client-verify")
            sec_protocol_options_set_verify_block(sec, { metadata, trustRef, complete in
                let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
                    complete(false); return
                }
                do {
                    let digest = try spkiFingerprint(for: leaf)
                    let match = constantTimeEqual(digest, pin.expectedFingerprint)
                    log("verify_block: server match=\(match)")
                    complete(match)
                } catch {
                    complete(false)
                }
            }, queue)
        }
    } else {
        let identity = try loadIdentity(workdir: workdir, name: identityName)
        print("client: using identity=\(identityName) spki_sha256=\(hex(try spkiFingerprint(for: identity.certificate)))")
        options = makeTLSOptions(
            localIdentity: identity.secIdentity,
            peerAuthenticationRequired: false,
            alpn: alpnMode,
            pin: pin,
            ticketMode: ticketMode,
            resumptionEnabled: resumptionEnabled,
            maxVersionOverride: maxVersion,
            log: { print("LOG[client] \($0)") }
        )
    }

    let client = SpikeClient(host: host, port: port, options: options)
    let code = client.run(timeout: timeout)
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first else {
    print("usage: nwlistener-spike <setup|listen|client> [--flag value ...]")
    exit(64)
}
let args = Args(Array(arguments.dropFirst()))

func cmdInspectP12(_ args: Args) throws {
    guard let path = args.value("p12"), let pass = args.value("pass") else {
        print("usage: inspect-p12 --p12 <path> --pass <passphrase>")
        exit(64)
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let kc = try TemporaryKeychain()
    defer { kc.cleanup() }
    let identity = try kc.importPKCS12(data: data, passphrase: pass)
    let fp = try spkiFingerprint(for: identity.certificate)
    print("inspect-p12: label=\(identity.label) spki_sha256=\(hex(fp))")
}

do {
    switch subcommand {
    case "setup": try cmdSetup(args)
    case "listen": try cmdListen(args)
    case "client": try cmdClient(args)
    case "inspect-p12": try cmdInspectP12(args)
    default:
        print("unknown subcommand: \(subcommand)")
        exit(64)
    }
} catch {
    print("ERROR: \(error)")
    exit(1)
}
