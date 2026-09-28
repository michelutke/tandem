package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.pairing.DeviceInfoProvider
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.PairingStateMachine
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.pairing.TrustCommitter
import dev.tandem.core.pairing.UnpairAction
import dev.tandem.core.pairing.qr.ParseInviteResult
import dev.tandem.core.pairing.qr.QrPayloadParser
import dev.tandem.core.pairing.revoke.RevokeHandler
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File
import java.net.InetAddress
import java.time.Clock
import java.util.Base64

private const val DEFAULT_IDENTITY_FILE = "harness-identity.bin"

/**
 * Entry point (E15-21): a stdin/stdout CLI wired to the real `core/crypto`, `core/transport` and
 * `core/pairing` modules. `--identity-file <path>` selects where the process's
 * [PersistentIdentityKeyStore] persists its identity (default: [DEFAULT_IDENTITY_FILE] in the
 * current working directory) so a restarted process reloads the same key. Reads one command per
 * line from stdin until `EXIT` or end of input; the synchronous readln loop itself is what
 * serializes command handling, one at a time -- [dispatcher] is [Dispatchers.IO], not a
 * single-thread dispatcher (E12-13 fix): [ByteStreamSession] needs to run its `ChannelMultiplexer`
 * read loop and its `VersionHandshake` write concurrently on the *same* dispatcher (both blocking,
 * both via `runInterruptible`, see that class's own kdoc and `ByteStreamSessionTest`'s
 * `Dispatchers.IO` usage) -- a single-thread dispatcher lets the read loop's blocking read()
 * monopolize the only thread forever, so the client's own `VersionHello` write never runs and the
 * handshake deadlocks (reproduced against the real Mac listener, E12-13).
 */
fun main(args: Array<String>) {
    HarnessConscryptProvider.ensureInstalled()
    val identityFile = File(argValue(args, "--identity-file") ?: DEFAULT_IDENTITY_FILE)
    val dispatcher = Dispatchers.IO
    val scope = CoroutineScope(SupervisorJob() + dispatcher)

    val identityKeyStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
    identityKeyStore.getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)
    val keyManager = IdentityKeyManager(identityKeyStore, PersistentIdentityKeyStore.IDENTITY_ALIAS)
    printIdentitySpkiFingerprint(keyManager)

    val knownPeerStore = HarnessKnownPeerStore(identityFile)
    val cli = HarnessCli(keyManager, dispatcher, scope, knownPeerStore)
    try {
        while (true) {
            val line = readlnOrNull() ?: break
            if (line.isBlank()) continue
            if (!cli.handle(line.trim())) break
        }
    } finally {
        cli.shutdown()
    }
}

private fun argValue(
    args: Array<String>,
    name: String,
): String? {
    val index = args.indexOf(name)
    return if (index >= 0 && index + 1 < args.size) args[index + 1] else null
}

/**
 * Prints this process's own identity SPKI fingerprint to stdout, in the same
 * `harness-identity-spki: <hex>` format as the Mac driver's own hook (see
 * `HarnessHooks.swift.printIdentitySpkiFingerprint`), so a driver script (E12-13) can seed this
 * identity into the Mac trust store without parsing the identity file itself.
 */
private fun printIdentitySpkiFingerprint(keyManager: IdentityKeyManager) {
    val certificate = keyManager.getCertificateChain(alias = null).single()
    val fingerprint = spkiFingerprint(certificate.publicKey.encoded)
    println("harness-identity-spki: ${hexOf(fingerprint)}")
}

/** Renders [fingerprint] the same way the Mac driver's own hooks do (hex, lowercase, no separator). */
private fun hexOf(fingerprint: SpkiFingerprint): String = fingerprint.bytes.joinToString(separator = "") { "%02x".format(it) }

/** Holds the CLI's session/pairing state across commands; see [main] for how it is wired up. */
private class HarnessCli(
    private val keyManager: IdentityKeyManager,
    private val dispatcher: CoroutineDispatcher,
    private val scope: CoroutineScope,
    private val knownPeerStore: HarnessKnownPeerStore,
) {
    private var session: TandemSession? = null
    private var connectedPeerFingerprintHex: String? = null
    private var pairing: PairingStateMachine? = null

    /**
     * Peers this process currently considers *not* paired any more (E14-20): either a live
     * `Revoke` was received on a Ready session, or this side explicitly `UNPAIR`ed. [connect]
     * refuses to dial any of these -- no socket is ever opened -- reproducing "the client never
     * dials it" (AC-12) without needing this harness to model a full client-side `TrustStore`.
     * In-memory only: unlike [knownPeerStore], nothing in this harness's scope needs this to
     * survive a process restart.
     */
    private val locallyRevoked = mutableSetOf<String>()

    /** Handles one command line; returns `false` if the CLI should stop reading further commands. */
    fun handle(line: String): Boolean {
        val parts = line.split(" ", limit = 2)
        val command = parts[0].uppercase()
        val rest = parts.getOrElse(1) { "" }
        when (command) {
            "CONNECT" -> connect(rest)
            "PAIR" -> pair(rest)
            "CONFIRM" -> confirm()
            "UNPAIR" -> unpair(rest)
            "TRUSTED" -> trusted(rest)
            "DISCONNECT" -> disconnect()
            "EXIT" -> {
                exit()
                return false
            }
            else -> println("ERROR unknown command \"$command\"")
        }
        return true
    }

    fun shutdown() {
        session?.close()
        pairing?.close()
    }

    private fun connect(argsLine: String) {
        val args = argsLine.split(" ").filter { it.isNotEmpty() }
        if (args.size != CONNECT_ARG_COUNT) {
            println("ERROR usage: CONNECT <host> <port> <spkiFingerprintBase64Url>")
            return
        }
        val (host, portArg, fingerprintArg) = args
        val port = portArg.toIntOrNull()
        val fingerprintBytes = runCatching { Base64.getUrlDecoder().decode(fingerprintArg) }.getOrNull()
        if (port == null || fingerprintBytes == null) {
            println("ERROR invalid CONNECT arguments")
            return
        }
        val fingerprint = SpkiFingerprint(fingerprintBytes)
        val fingerprintHex = hexOf(fingerprint)

        // AC-12: this side has already unpaired this peer, so a forced CONNECT dials with the
        // same (now-empty) pin list the real app would have -- the real client-side pin check
        // (PinningTrustManager, over a real TLS handshake) rejects the server, not a harness-side
        // shortcut. A TLS handshake failure exchanges zero *application* bytes (SPEC.md's AC-12
        // wording), matching "forced dial fails the client-side pin check with 0 application bytes".
        runCatching {
            val pinSource =
                if (fingerprintHex in locallyRevoked) PinSource { emptyList() } else PinSource { listOf(fingerprint) }
            val factory =
                SslClientFactory(keyManager, PinningTrustManager(pinSource), JvmConscryptSessionTicketDisabler())
            val socket = factory.createSocket()
            runBlocking(dispatcher) {
                val stream = withContext(dispatcher) { factory.connect(socket, InetAddress.getByName(host), port) }
                val newSession = ByteStreamSession(stream, Clock.systemUTC(), dispatcher)
                val readyOrFailed =
                    newSession.state.first { it is ConnectionState.Ready || it is ConnectionState.Failed }
                when (val outcome = readyOrFailed) {
                    is ConnectionState.Ready -> {
                        session = newSession
                        connectedPeerFingerprintHex = fingerprintHex
                        knownPeerStore.recordPinned(fingerprintHex)
                        watchForRevoke(newSession, fingerprint)
                        println("OK CONNECTED")
                    }
                    is ConnectionState.Failed -> println("ERROR ${classify(fingerprintHex)} ${outcome.reason}")
                    else -> Unit
                }
            }
        }.onFailure { println("ERROR ${classify(fingerprintHex)} ${it.message}") }
    }

    /**
     * SPEC.md #errors-and-close-codes row 7 / row 2 (E12-16, UC-07): a failed non-pairing dial maps
     * to `REVOKED` ("no longer paired") if this side had previously pinned [fingerprintHex]
     * ([HarnessKnownPeerStore.hasEverPinned], surviving a process restart), else to `PIN_MISMATCH`
     * (an unrecognized key is indistinguishable from a never-known one, D-23).
     */
    private fun classify(fingerprintHex: String): String =
        if (knownPeerStore.hasEverPinned(fingerprintHex)) "REVOKED" else "PIN_MISMATCH"

    /**
     * Watches [activeSession]'s CONTROL channel for a `Revoke` from [peer] (E14-20, mirroring the
     * real E14-19 receiver: a Revoke on a Ready session deletes this side's own belief that it is
     * still paired with [peer] and closes the session; a Revoke before/without Ready is impossible
     * here since this is only ever called after `OK CONNECTED`). Reuses the real
     * [RevokeHandler] rather than reimplementing its logic.
     */
    private fun watchForRevoke(
        activeSession: TandemSession,
        peer: SpkiFingerprint,
    ) {
        scope.launch {
            activeSession.receive(Channel.CHANNEL_CONTROL).collect { envelope ->
                if (envelope.payloadCase == Envelope.PayloadCase.REVOKE) {
                    val handler = RevokeHandler(activeSession, peer) { fp -> locallyRevoked += hexOf(fp) }
                    if (handler.handleRevoke()) {
                        println("EVENT REVOKED ${hexOf(peer)}")
                    }
                }
            }
        }
    }

    /**
     * `UNPAIR <spkiFingerprintBase64Url>` (E14-20): reuses the real [UnpairAction] (E14-12/E14-13)
     * -- deletes this side's own belief that it is paired with that peer first, then, only if
     * [session] is Ready for that exact peer, sends Revoke on CONTROL and closes.
     */
    private fun unpair(fingerprintArg: String) {
        val fingerprintBytes = runCatching { Base64.getUrlDecoder().decode(fingerprintArg.trim()) }.getOrNull()
        if (fingerprintBytes == null) {
            println("ERROR usage: UNPAIR <spkiFingerprintBase64Url>")
            return
        }
        val fingerprint = SpkiFingerprint(fingerprintBytes)
        val fingerprintHex = hexOf(fingerprint)
        val activeSession = session.takeIf { connectedPeerFingerprintHex == fingerprintHex }

        val action = UnpairAction(
            trustRemover = { fp -> locallyRevoked += hexOf(fp) },
            purgeRegistry = PeerDataPurgeRegistry(),
        )
        runBlocking(dispatcher) { action.unpair(fingerprint, activeSession) }
        if (activeSession != null) {
            session = null
            connectedPeerFingerprintHex = null
        }
        println("OK UNPAIRED")
    }

    /**
     * `TRUSTED <spkiFingerprintBase64Url>` (E14-20): `OK FALSE` once this fingerprint has been
     * revoked/unpaired (see [locallyRevoked]), `OK TRUE` otherwise -- the harness's stand-in for
     * "does the phone still show a trust record for this peer" (scoped to a peer this process has
     * actually connected to; this harness tracks no wider trust store, E15-21 scope).
     */
    private fun trusted(fingerprintArg: String) {
        val fingerprintBytes = runCatching { Base64.getUrlDecoder().decode(fingerprintArg.trim()) }.getOrNull()
        if (fingerprintBytes == null) {
            println("ERROR usage: TRUSTED <spkiFingerprintBase64Url>")
            return
        }
        val fingerprintHex = hexOf(SpkiFingerprint(fingerprintBytes))
        println(if (fingerprintHex in locallyRevoked) "OK FALSE" else "OK TRUE")
    }

    private fun pair(qrUri: String) {
        when (val result = QrPayloadParser.parse(qrUri)) {
            is ParseInviteResult.Rejected -> println("ERROR ${result.error}")
            is ParseInviteResult.Accepted -> {
                val connector = HarnessPairingConnector(keyManager, dispatcher)
                val trustCommitter =
                    TrustCommitter { fingerprint, macName, _ ->
                        println("EVENT PAIRED $macName ${fingerprint.base64Url}")
                    }
                val machine =
                    PairingStateMachine(
                        Clock.systemUTC(),
                        dispatcher,
                        connector,
                        trustCommitter,
                        result.invite,
                        HarnessDeviceInfoProvider,
                    )
                pairing = machine
                scope.launch { machine.state.collect { println("EVENT ${harnessEventLine(it)}") } }
                machine.start()
                println("OK PAIRING_STARTED")
            }
        }
    }

    private fun confirm() {
        val machine = pairing
        if (machine == null) {
            println("ERROR no pairing in progress")
            return
        }
        runBlocking(dispatcher) { machine.confirmCodesMatch() }
        println("OK CONFIRMED")
    }

    /**
     * Renders a [PairingState] for this harness's own `EVENT` line -- unlike [PairingState]'s own
     * `toString()` (invariant 7: redacted in every ordinary app log), the harness's own driver
     * script (`tools/harness/integration/e14-16.sh`) must read the actual confirmation code back to
     * assert it equals the one the Mac prints, so [AwaitingAccept]/[AwaitingUserConfirm] print their
     * real, unredacted [PairingState.AwaitingAccept.code]/[PairingState.AwaitingUserConfirm.code]
     * here -- mirroring the Mac harness's own `HarnessHooks.onConfirmationPending` doing the same
     * over stdout. Every other state falls back to its own (harmless, code-free) `toString()`.
     */
    private fun harnessEventLine(state: PairingState): String =
        when (state) {
            is PairingState.AwaitingAccept -> "AwaitingAccept(code=${state.code})"
            is PairingState.AwaitingUserConfirm -> "AwaitingUserConfirm(code=${state.code}, macName=${state.macName})"
            else -> state.toString()
        }

    private fun disconnect() {
        session?.close()
        session = null
        connectedPeerFingerprintHex = null
        println("OK DISCONNECTED")
    }

    private fun exit() {
        shutdown()
        println("OK BYE")
    }

    private companion object {
        const val CONNECT_ARG_COUNT = 3
    }
}

/** Fixed, non-hardware-identifying device info for this JVM harness process (E14-06). */
private object HarnessDeviceInfoProvider : DeviceInfoProvider {
    override fun displayName(): String = "JVM Harness Client"

    override fun model(): String = "jvm-client"
}
