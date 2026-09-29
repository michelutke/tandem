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

    private static func decodeFingerprintHex(_ hex: String) -> SpkiFingerprint? {
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
        return try? SpkiFingerprint(bytes: Data(bytes))
    }

    private static let sendRawRingArgCount = 3
    private static let nanosPerMilli: UInt64 = 1_000_000
}
#endif
