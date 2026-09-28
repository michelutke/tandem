package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PairingProof
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
import dev.tandem.protocol.v1.deviceInfo
import dev.tandem.protocol.v1.pairRequest
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.net.InetAddress
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.time.Clock
import java.util.Base64

private const val RAW_CHALLENGE_TIMEOUT_MS = 10_000L
private const val RAW_OUTCOME_TIMEOUT_MS = 15_000L

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

/** Lowercase, no-separator hex, matching [hexOf]'s rendering -- for the raw E15-09 commands' `cb`/proof bytes. */
private fun ByteArray.toLowerHex(): String = joinToString(separator = "") { "%02x".format(it) }

/** Decodes lowercase or uppercase hex into bytes, or `null` if [this] is not valid even-length hex. */
private fun String.decodeHex(): ByteArray? {
    if (length % 2 != 0 || isEmpty()) return null
    return runCatching {
        ByteArray(length / 2) { i -> ((this[2 * i].digitToInt(16) shl 4) or this[2 * i + 1].digitToInt(16)).toByte() }
    }.getOrNull()
}

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
     * State for the `RAWOPEN`/`RAWSEND`/`RAWSENDPROOF`/`RAWREVOKE`/`RAWCLOSE` commands (E15-09
     * mitm-lab pairing-abuse scenarios): a *separate* low-level pairing-candidate connection from
     * [session]/[pairing] above, deliberately bypassing [PairingStateMachine]/[PairRequestBuilder]
     * so a scenario script can construct a wrong, replayed, or malformed `PairRequest` (or a
     * `Revoke` sent before `PairAccepted`) that the real state machine would never produce.
     */
    private var rawSession: TandemSession? = null
    private var rawMacSpkiDer: ByteArray? = null
    private var rawPhoneSpkiDer: ByteArray? = null
    private var rawChallenge: ByteArray? = null

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
            "RAWOPEN" -> rawOpen(rest)
            "RAWSEND" -> rawSend(rest)
            "RAWSENDPROOF" -> rawSendProof(rest)
            "RAWREVOKE" -> rawRevoke()
            "RAWCLOSE" -> rawClose()
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

    /**
     * `RAWOPEN <host> <port> <macFpSpkiFingerprintBase64Url>` (E15-09): dials a fresh mTLS
     * connection with this process's real identity, exactly like [connect], but keeps the raw
     * [TandemSession] in [rawSession] instead of driving it through a normal Ready session or the
     * real [PairingStateMachine]. A rejection at the TLS verify callback itself (no pairing window
     * open, a candidate already in flight, or the window's attempt budget exhausted -- SPEC.md
     * #pairing "Pairing window") surfaces here as [ConnectionState.Failed] before any `CONTROL`
     * frame is ever exchanged, printed as `ERROR HANDSHAKE_REJECTED <reason>`.
     *
     * On a successful handshake, waits up to [RAW_CHALLENGE_TIMEOUT_MS] for the first non-Heartbeat
     * `CONTROL` frame: a `PairChallenge` (the normal pairing-candidate case) is captured into
     * [rawChallenge] and printed as `OK OPENED <cbHex>`; anything else prints `OK OPENED
     * NOCHALLENGE` (this connection's certificate is already trusted -- SPEC.md #pairing "Frame
     * order": the Mac only ever sends `PairChallenge` to a *pairing-candidate* connection, never to
     * an already-trusted one -- E15-09 scenarios 1/6/7 deliberately reconnect with an
     * already-trusted identity and inject a `PairRequest` anyway).
     */
    private fun rawOpen(argsLine: String) {
        val args = argsLine.split(" ").filter { it.isNotEmpty() }
        if (args.size != CONNECT_ARG_COUNT) {
            println("ERROR usage: RAWOPEN <host> <port> <spkiFingerprintBase64Url>")
            return
        }
        val (host, portArg, fingerprintArg) = args
        val port = portArg.toIntOrNull()
        val fingerprintBytes = runCatching { Base64.getUrlDecoder().decode(fingerprintArg) }.getOrNull()
        if (port == null || fingerprintBytes == null) {
            println("ERROR invalid RAWOPEN arguments")
            return
        }
        rawSession?.close()
        rawSession = null
        rawMacSpkiDer = null
        rawPhoneSpkiDer = null
        rawChallenge = null

        val fingerprint = SpkiFingerprint(fingerprintBytes)
        runCatching {
            val factory =
                SslClientFactory(
                    keyManager,
                    PinningTrustManager(PinSource { listOf(fingerprint) }),
                    JvmConscryptSessionTicketDisabler(),
                )
            val socket = factory.createSocket()
            runBlocking(dispatcher) {
                val stream = withContext(dispatcher) { factory.connect(socket, InetAddress.getByName(host), port) }
                val newSession = ByteStreamSession(stream, Clock.systemUTC(), dispatcher)
                when (val outcome = newSession.state.first { it is ConnectionState.Ready || it is ConnectionState.Failed }) {
                    is ConnectionState.Failed -> {
                        newSession.close()
                        println("ERROR HANDSHAKE_REJECTED ${outcome.reason}")
                    }
                    is ConnectionState.Ready -> {
                        rawSession = newSession
                        rawMacSpkiDer = socket.session.peerCertificates.first().let { (it as java.security.cert.X509Certificate).publicKey.encoded }
                        rawPhoneSpkiDer = keyManager.getCertificateChain(alias = null).single().publicKey.encoded
                        when (val challengeOutcome = awaitFirstNonHeartbeat(newSession, RAW_CHALLENGE_TIMEOUT_MS)) {
                            is RawWaitOutcome.Success -> {
                                val envelope = challengeOutcome.envelope
                                if (envelope.payloadCase == Envelope.PayloadCase.PAIR_CHALLENGE) {
                                    val challenge = envelope.pairChallenge.challenge.toByteArray()
                                    rawChallenge = challenge
                                    println("OK OPENED ${challenge.toLowerHex()}")
                                } else {
                                    println("OK OPENED NOCHALLENGE")
                                }
                            }
                            RawWaitOutcome.ConnectionLost -> println("ERROR CONNECTION_CLOSED")
                            RawWaitOutcome.TimedOut -> println("OK OPENED NOCHALLENGE")
                        }
                    }
                    else -> Unit
                }
            }
        }.onFailure { println("ERROR HANDSHAKE_REJECTED ${it.message}") }
    }

    /**
     * `RAWSEND <secretBase64Url> [WRONGKEY] [CB=<cbHex>]` (E15-09): computes a real `proof` using
     * the real, injected [PairingProof] formula (SPEC.md #pairing "Proof computation") and this
     * process's real [rawMacSpkiDer]/[rawPhoneSpkiDer] -- over [rawChallenge] (captured by
     * [rawOpen] for the *current* raw session) unless `CB=<cbHex>` overrides which channel-binding
     * value goes into the transcript (scenario `mitmLab_pairRequestReplayedOnNewTlsSession`: a real
     * proof computed with the *current* session's own `macSpkiDer`/`phoneSpkiDer` but an *old*
     * session's `cb`, proving channel binding rejects it). `WRONGKEY` substitutes a freshly
     * generated, unrelated P-256 key's SPKI DER in place of [rawPhoneSpkiDer] (scenario
     * `mitmLab_proofForDifferentPhoneKey`: the Mac always recomputes with the key it actually saw
     * on *this* handshake, never a field from the request body, so this must -- and does --
     * produce `BAD_PROOF`).
     */
    private fun rawSend(argsLine: String) {
        val parts = argsLine.split(" ").filter { it.isNotEmpty() }
        val secretArg = parts.getOrNull(0)
        var wrongKey = false
        var cbOverrideHex: String? = null
        for (flag in parts.drop(1)) {
            when {
                flag.equals("WRONGKEY", ignoreCase = true) -> wrongKey = true
                flag.startsWith("CB=", ignoreCase = true) -> cbOverrideHex = flag.substringAfter("=")
            }
        }
        val macSpkiDer = rawMacSpkiDer
        val phoneSpkiDer = rawPhoneSpkiDer
        val challenge = cbOverrideHex?.decodeHex() ?: rawChallenge
        val secretBytes = secretArg?.let { runCatching { Base64.getUrlDecoder().decode(it) }.getOrNull() }
        if (secretBytes == null || macSpkiDer == null || challenge == null || phoneSpkiDer == null) {
            println("ERROR usage: RAWSEND <secretBase64Url> [WRONGKEY] [CB=<cbHex>] (after a successful RAWOPEN with a challenge)")
            return
        }
        val effectivePhoneSpkiDer = if (wrongKey) generateUnrelatedSpkiDer() else phoneSpkiDer
        val proof = PairingProof.compute(secretBytes, macSpkiDer, effectivePhoneSpkiDer, challenge)
        sendRawPairRequest(proof)
    }

    /**
     * `RAWSENDPROOF <proofHex>` (E15-09): sends a `PairRequest` carrying literal, already-computed
     * proof bytes rather than deriving them here -- for byte-level replay of a proof value captured
     * from an earlier, real `RAWSEND` (scenarios `mitmLab_replayedPairRequestAfterCompletion`,
     * `mitmLab_pairRequestReplayedOnNewTlsSession`) or an arbitrary bad/random proof (scenario
     * `mitmLab_badProofRejection`, the `mitmLab_fourthAttemptAfterThreeFailures` exhaustion loop).
     */
    private fun rawSendProof(proofHexArg: String) {
        val proof = proofHexArg.trim().decodeHex()
        if (proof == null) {
            println("ERROR usage: RAWSENDPROOF <proofHex>")
            return
        }
        sendRawPairRequest(proof)
    }

    private fun sendRawPairRequest(proof: ByteArray) {
        val activeSession = rawSession
        if (activeSession == null) {
            println("ERROR no raw session open (RAWOPEN first)")
            return
        }
        val request =
            pairRequest {
                this.proof = ByteString.copyFrom(proof)
                deviceInfo =
                    deviceInfo {
                        displayName = "E15-09 mitm-lab"
                        model = "jvm-raw-client"
                        appVersion = ""
                    }
            }
        println("OK SENT ${proof.toLowerHex()}")
        runBlocking(dispatcher) {
            activeSession.send(Channel.CHANNEL_CONTROL) { pairRequest = request }
        }
        printRawPairOutcome(activeSession)
    }

    /**
     * `RAWREVOKE` (E15-09 scenario `mitmLab_revokeOnPairingCandidateConnection`): sends `Revoke {}`
     * on the still-open raw pairing-candidate connection instead of a `PairRequest` -- an
     * unexpected payload at this point in the frame order (SPEC.md #pairing "Frame order on a
     * pairing-candidate connection", step 4), which the Mac closes with `PAIRING_FAILED` and never
     * turns into `PairAccepted` or a committed trust record.
     */
    private fun rawRevoke() {
        val activeSession = rawSession
        if (activeSession == null) {
            println("ERROR no raw session open (RAWOPEN first)")
            return
        }
        runBlocking(dispatcher) {
            activeSession.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} }
        }
        println("OK SENT_REVOKE")
        printRawPairOutcome(activeSession)
    }

    private fun rawClose() {
        rawSession?.close()
        rawSession = null
        rawMacSpkiDer = null
        rawPhoneSpkiDer = null
        rawChallenge = null
        println("OK RAWCLOSED")
    }

    /**
     * Prints the terminal outcome of a raw pairing attempt/`Revoke`: `EVENT PAIR_ACCEPTED`,
     * `EVENT PAIR_REJECTED <reasonEnumName>` (SPEC.md #pairing "`PairRejected` wire collapse":
     * always `PAIR_REJECTED_REASON_REJECTED_BY_OWNER` or `PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE`),
     * `EVENT PAIR_CLOSED` (the connection dropped with no `PairRejected` -- `TIMEOUT`,
     * `MALFORMED_FRAME`, or the peer simply closing), or `EVENT PAIR_TIMEOUT` (no terminal frame
     * and no close within [RAW_OUTCOME_TIMEOUT_MS]).
     */
    private fun printRawPairOutcome(activeSession: TandemSession) {
        val outcome =
            runBlocking(dispatcher) {
                withTimeoutOrNull(RAW_OUTCOME_TIMEOUT_MS) {
                    waitForControlEnvelope(activeSession) {
                        it.payloadCase == Envelope.PayloadCase.PAIR_ACCEPTED ||
                            it.payloadCase == Envelope.PayloadCase.PAIR_REJECTED
                    }
                }
            }
        when (outcome) {
            null, RawWaitOutcome.TimedOut -> println("EVENT PAIR_TIMEOUT")
            RawWaitOutcome.ConnectionLost -> println("EVENT PAIR_CLOSED")
            is RawWaitOutcome.Success -> {
                val envelope = outcome.envelope
                if (envelope.payloadCase == Envelope.PayloadCase.PAIR_ACCEPTED) {
                    println("EVENT PAIR_ACCEPTED")
                } else {
                    println("EVENT PAIR_REJECTED ${envelope.pairRejected.reason}")
                }
            }
        }
    }

    /** Sealed outcome for [waitForControlEnvelope]/[awaitFirstNonHeartbeat], mirroring [PairingStateMachine]'s own. */
    private sealed class RawWaitOutcome {
        class Success(
            val envelope: Envelope,
        ) : RawWaitOutcome()

        data object ConnectionLost : RawWaitOutcome()

        data object TimedOut : RawWaitOutcome()
    }

    /**
     * Races [predicate] matching a `CONTROL` [Envelope] against [activeSession]'s connection
     * dropping -- the same shape as [PairingStateMachine]'s private `waitForControlEnvelope`,
     * duplicated here since this class deliberately drives its own raw session outside that state
     * machine.
     */
    private suspend fun waitForControlEnvelope(
        activeSession: TandemSession,
        predicate: (Envelope) -> Boolean,
    ): RawWaitOutcome =
        coroutineScope {
            val received = async { activeSession.receive(Channel.CHANNEL_CONTROL).first(predicate) }
            val disconnected = async { activeSession.state.first { it is ConnectionState.Disconnected } }
            try {
                select {
                    received.onAwait { RawWaitOutcome.Success(it) }
                    disconnected.onAwait { RawWaitOutcome.ConnectionLost }
                }
            } finally {
                received.cancel()
                disconnected.cancel()
            }
        }

    /**
     * Like [waitForControlEnvelope], but bounded by [timeoutMs] and skipping `Heartbeat` frames
     * (SPEC.md #pairing "Frame order", step 4: `Heartbeat` is exempt from wrong-payload handling in
     * both directions) rather than treating the first arriving frame of any type as terminal.
     */
    private suspend fun awaitFirstNonHeartbeat(
        activeSession: TandemSession,
        timeoutMs: Long,
    ): RawWaitOutcome =
        withTimeoutOrNull(timeoutMs) {
            waitForControlEnvelope(activeSession) { it.payloadCase != Envelope.PayloadCase.HEARTBEAT }
        } ?: RawWaitOutcome.TimedOut

    /** A P-256 SPKI DER for a key nobody's certificate uses -- SPEC.md #pairing "Proof computation" wrong-key case. */
    private fun generateUnrelatedSpkiDer(): ByteArray {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        return generator.generateKeyPair().public.encoded
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
