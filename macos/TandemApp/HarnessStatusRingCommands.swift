#if DEBUG
import Foundation
import TandemCrypto
import TandemProtocol

/// DEBUG-only interactive command loop for E23-08's Mac-initiated Ring/RingStop scenarios: reads
/// one command per line from stdin (mirroring the JVM harness client's own stdin loop,
/// `HarnessCli.kt`), so a driver script can command this already-running listener process to send
/// Ring/RingStop to a connected peer without reaching into it. Gated by
/// `-HarnessInteractiveCommands YES` -- independent of, but always paired with in this issue's own
/// scripts, `-HarnessStreamStatus YES` (`HarnessRevokeAwareSessionRegistry`'s own kdoc).
///
/// `FINDPHONE <fpHex>` reuses the real ``FindPhoneViewModel`` (E23-07) -- one instance per
/// fingerprint, retained for this process's lifetime -- toggling idle/ringing exactly like the
/// menu bar's own "Find Phone"/"Stop Ringing" action would: `Ring` on the first call,
/// `RingStop{origin: mac}` on the next. `SENDRAWRING <fpHex> <count> <intervalMs>` bypasses that
/// state machine to send `count` raw `Ring` frames spaced `intervalMs` apart -- E23-08's flood
/// scenario (20 `Ring`s in 5s) isn't reachable through `FindPhoneViewModel.select()`, which always
/// alternates `Ring`/`RingStop`.
///
/// `SENDINPUT <fpHex> <TAP|TAPOUT|SETTEXT> <count> <perSecond> <NONE|RANDOM|sessionIdHex> [text]`
/// (E62-08) sends `count` crafted `InputEvent`s on the INPUT channel at `perSecond` with the given
/// mirror-session reference (`NONE`: absent, `RANDOM`: 16 fresh bytes). `TAP` lands inside any real
/// stream, `TAPOUT` far outside every one, `SETTEXT` carries `text` (the log-audit canary). Nothing
/// is ever sent by a real mirror window here, so this is how a scenario proves the phone drops input
/// that no user-started session authorizes. `MIRRORREQUEST <fpHex>` sends a `MirrorRequest` (the phone
/// then shows its start prompt) and `MIRRORSTOP` cancels the media connections bound under
/// `-HarnessMediaTickets YES`, so a scenario can start and end a real mirror session.
@MainActor
enum HarnessStatusRingCommands {
    private static var findPhoneViewModels: [SpkiFingerprint: FindPhoneViewModel] = [:]

    /// Starts the stdin command-reading loop on a background thread if `-HarnessInteractiveCommands
    /// YES` is set; a no-op otherwise. `readLine()` blocks that thread only, never the caller.
    nonisolated static func startIfRequested(registry: ControlSessionRegistry) {
        guard UserDefaults.standard.bool(forKey: "HarnessInteractiveCommands") else { return }
        let thread = Thread {
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                Task { await handle(trimmed, registry: registry) }
            }
        }
        thread.start()
    }

    private static func handle(_ line: String, registry: ControlSessionRegistry) async {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first else { return }
        let args = Array(parts.dropFirst())
        switch command.uppercased() {
        case "FINDPHONE":
            await findPhone(args, registry: registry)
        case "SENDRAWRING":
            await sendRawRing(args, registry: registry)
        case "SENDINPUT":
            await sendInput(args, registry: registry)
        case "MIRRORREQUEST":
            await sendMirrorRequest(args, registry: registry)
        case "MIRRORSTOP":
            print("OK CLOSED_MEDIA \(HarnessMediaTickets.closeBoundConnections())")
            fflush(stdout)
        default:
            print("ERROR unknown command \"\(command)\"")
            fflush(stdout)
        }
    }

    private static func findPhone(_ args: [String], registry: ControlSessionRegistry) async {
        guard let fingerprintHex = args.first, let fingerprint = decodeFingerprintHex(fingerprintHex) else {
            print("ERROR usage: FINDPHONE <spkiFingerprintHex>")
            fflush(stdout)
            return
        }
        guard let session = await registry.session(for: fingerprint) else {
            print("ERROR NO_SESSION")
            fflush(stdout)
            return
        }
        let viewModel = findPhoneViewModels[fingerprint] ?? FindPhoneViewModel(session: session)
        findPhoneViewModels[fingerprint] = viewModel
        viewModel.select()
        print("OK SELECTED label=\(viewModel.label)")
        fflush(stdout)
    }

    private static func sendRawRing(_ args: [String], registry: ControlSessionRegistry) async {
        guard args.count == sendRawRingArgCount,
              let fingerprint = decodeFingerprintHex(args[0]),
              let count = Int(args[1]),
              let intervalMs = UInt64(args[2]) else {
            print("ERROR usage: SENDRAWRING <spkiFingerprintHex> <count> <intervalMs>")
            fflush(stdout)
            return
        }
        guard let session = await registry.session(for: fingerprint) else {
            print("ERROR NO_SESSION")
            fflush(stdout)
            return
        }
        for index in 0..<count {
            try? await session.send(.status, payload: .ring(Tandem_V1_Ring()))
            if index < count - 1 {
                try? await Task.sleep(nanoseconds: intervalMs * nanosPerMilli)
            }
        }
        print("OK SENT_RAW_RINGS \(count)")
        fflush(stdout)
    }

    private static func sendMirrorRequest(_ args: [String], registry: ControlSessionRegistry) async {
        guard let fingerprintHex = args.first, let fingerprint = decodeFingerprintHex(fingerprintHex) else {
            print("ERROR usage: MIRRORREQUEST <spkiFingerprintHex>")
            fflush(stdout)
            return
        }
        guard let session = await registry.session(for: fingerprint) else {
            print("ERROR NO_SESSION")
            fflush(stdout)
            return
        }
        try? await session.send(.control, payload: .mirrorRequest(Tandem_V1_MirrorRequest()))
        print("OK SENT_MIRROR_REQUEST")
        fflush(stdout)
    }

    private static func sendInput(_ args: [String], registry: ControlSessionRegistry) async {
        guard args.count >= sendInputMinArgCount,
              let fingerprint = decodeFingerprintHex(args[0]),
              let count = Int(args[2]),
              let perSecond = Int(args[3]), perSecond > 0,
              let sessionId = inputSessionId(args[4]),
              let template = inputEvent(
                  kind: args[1].uppercased(), sessionId: sessionId, text: args.dropFirst(5).first)
        else {
            print("ERROR usage: SENDINPUT <spkiFingerprintHex> <TAP|TAPOUT|SETTEXT> <count> <perSecond> "
                + "<NONE|RANDOM|sessionIdHex> [text]")
            fflush(stdout)
            return
        }
        guard let session = await registry.session(for: fingerprint) else {
            print("ERROR NO_SESSION")
            fflush(stdout)
            return
        }
        let perTick = max(perSecond / inputTicksPerSecond, 1)
        let tickNanos = nanosPerSecond * UInt64(perTick) / UInt64(perSecond)
        var sent = 0
        while sent < count {
            for _ in 0..<min(perTick, count - sent) {
                try? await session.send(.input, payload: .inputEvent(template))
                sent += 1
            }
            try? await Task.sleep(nanoseconds: tickNanos)
        }
        print("OK SENT_INPUT \(sent)")
        fflush(stdout)
    }

    private static func inputSessionId(_ argument: String) -> Data? {
        switch argument.uppercased() {
        case "NONE": return Data()
        case "RANDOM": return Data((0..<inputSessionIdByteCount).map { _ in UInt8.random(in: 0...255) })
        default: return decodeHex(argument)
        }
    }

    private static func inputEvent(kind: String, sessionId: Data, text: String?) -> Tandem_V1_InputEvent? {
        var event = Tandem_V1_InputEvent()
        event.sessionID = sessionId
        switch kind {
        case "TAP":
            var tap = Tandem_V1_Tap()
            tap.x = inputInRangeCoordinate
            tap.y = inputInRangeCoordinate
            event.tap = tap
        case "TAPOUT":
            var tap = Tandem_V1_Tap()
            tap.x = inputOutOfRangeCoordinate
            tap.y = inputOutOfRangeCoordinate
            event.tap = tap
        case "SETTEXT":
            var setText = Tandem_V1_SetText()
            setText.text = text ?? ""
            event.setText = setText
        default:
            return nil
        }
        return event
    }

    private static func decodeFingerprintHex(_ hex: String) -> SpkiFingerprint? {
        guard let bytes = decodeHex(hex) else { return nil }
        return try? SpkiFingerprint(bytes: bytes)
    }

    private static func decodeHex(_ hex: String) -> Data? {
        guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static let sendRawRingArgCount = 3
    private static let sendInputMinArgCount = 5
    private static let inputTicksPerSecond = 100
    private static let inputSessionIdByteCount = 16
    private static let inputInRangeCoordinate: UInt32 = 200
    private static let inputOutOfRangeCoordinate: UInt32 = 4_000_000_000
    private static let nanosPerSecond: UInt64 = 1_000_000_000
    private static let nanosPerMilli: UInt64 = 1_000_000
}
#endif
