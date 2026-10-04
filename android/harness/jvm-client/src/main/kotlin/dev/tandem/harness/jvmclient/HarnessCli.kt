package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.IdentityKeyStore
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
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.feature.status.StatusPublisher
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.NetworkType
import dev.tandem.protocol.v1.RotationRejectReason
import dev.tandem.protocol.v1.creditGrant
import dev.tandem.protocol.v1.deviceInfo
import dev.tandem.protocol.v1.deviceStatus
import dev.tandem.protocol.v1.heartbeat
import dev.tandem.protocol.v1.notificationPosted
import dev.tandem.protocol.v1.pairRequest
import dev.tandem.protocol.v1.requestMediaTicket
import dev.tandem.protocol.v1.rotationAck
import dev.tandem.protocol.v1.rotationChallenge
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.time.Clock
import java.util.Base64
import java.util.concurrent.atomic.AtomicInteger

private const val RAW_CHALLENGE_TIMEOUT_MS = 10_000L
private const val FLOOD_TICKS_PER_SECOND = 10
private const val MILLIS_PER_SECOND = 1_000L
private const val RAW_OUTCOME_TIMEOUT_MS = 15_000L
private const val MEDIA_CLOSE_TIMEOUT_MS = 15_000
private const val NANOS_PER_MILLI = 1_000_000L

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
    val displayName = argValue(args, "--display-name") ?: HarnessDeviceInfoProvider.DEFAULT_DISPLAY_NAME
    val dispatcher = Dispatchers.IO
    val scope = CoroutineScope(SupervisorJob() + dispatcher)

    val identityKeyStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
    identityKeyStore.getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)
    val keyManager = IdentityKeyManager(identityKeyStore, PersistentIdentityKeyStore.IDENTITY_ALIAS)
    printIdentitySpkiFingerprint(keyManager)

    val knownPeerStore = HarnessKnownPeerStore(identityFile)
    val deviceInfoProvider = HarnessDeviceInfoProvider(displayName)
    val rawRotation = RawRotation(requireNotNull(identityKeyStore.get(PersistentIdentityKeyStore.IDENTITY_ALIAS)))
    val cli = HarnessCli(keyManager, dispatcher, scope, knownPeerStore, deviceInfoProvider, rawRotation)
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
    private val deviceInfoProvider: DeviceInfoProvider,
    private val rawRotation: RawRotation,
) {
    private var session: TandemSession? = null
    private var connectedPeerFingerprintHex: String? = null
    private var pairing: PairingStateMachine? = null

    /**
     * E23-08 status/ring wiring, (re)created on a successful [connect] and torn down on
     * [disconnect]/[exit]: [statusFlow] feeds the real [StatusPublisher] (E23-03) so the `STATUS`
     * command exercises its actual throttle/coalescing logic against [session], and
     * [ringWatchJob] drives [ringReactor] (E23-05/E23-06/E23-07's documented behavior, see that
     * class's own kdoc for why it isn't the real `RingController`) off every `Ring`/`RingStop`
     * this session's STATUS channel actually receives.
     */
    private var statusFlow: MutableSharedFlow<DeviceStatus>? = null
    private var statusPublisher: StatusPublisher? = null
    private var ringReactor: HarnessRingReactor? = null
    private var ringWatchJob: Job? = null

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
    private var rawRotationChallenge: ByteArray? = null

    /**
     * Peers this process currently considers *not* paired any more (E14-20): either a live
     * `Revoke` was received on a Ready session, or this side explicitly `UNPAIR`ed. [connect]
     * refuses to dial any of these -- no socket is ever opened -- reproducing "the client never
     * dials it" (AC-12) without needing this harness to model a full client-side `TrustStore`.
     * In-memory only: unlike [knownPeerStore], nothing in this harness's scope needs this to
     * survive a process restart.
     */
    private val locallyRevoked = mutableSetOf<String>()

    private val heartbeatsReceived = AtomicInteger()

    private val heldMediaStreams = mutableListOf<ByteStream>()

    private var remoteInput: RemoteInputHarness? = null
    private var inputWatchJob: Job? = null

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
            "STATUS" -> status(rest)
            "RINGSTATE" -> ringState()
            "INPUTWATCH" -> inputWatch()
            "INPUTSTATS" -> println(remoteInput?.statsLine() ?: "ERROR no INPUTWATCH running")
            "DISCONNECT" -> disconnect()
            "SENDNOTIFICATIONS" -> sendNotifications(rest)
            "FLOOD" -> flood(rest)
            "RAWOPEN" -> rawOpen(rest)
            "RAWSEND" -> rawSend(rest)
            "RAWSENDPROOF" -> rawSendProof(rest)
            "RAWREVOKE" -> rawRevoke()
            "RAWCLOSE" -> rawClose()
            "RAWKEYGEN" -> println("OK KEYGEN ${rawRotation.generateHeldKey()}")
            "RAWCHALLENGE" -> rawRotationChallengeCommand()
            "RAWROTATE" -> rawRotate(rest)
            "RAWMACROTATION" -> rawMacRotation(rest)
            "RAWTICKET" -> rawTicket()
            "MEDIAOPEN" -> mediaOpen(rest)
            "EXIT" -> {
                exit()
                return false
            }
            else -> println("ERROR unknown command \"$command\"")
        }
        return true
    }

    fun shutdown() {
        inputWatchJob?.cancel()
        heldMediaStreams.forEach { it.closeAbruptly() }
        session?.close()
        pairing?.close()
        stopStatusAndRingWiring()
    }

    /**
     * Builds this connection's [statusFlow]/[statusPublisher]/[ringReactor]/[ringWatchJob]
     * (E23-08), replacing whatever a previous connection left wired up.
     */
    private fun startStatusAndRingWiring(activeSession: TandemSession) {
        stopStatusAndRingWiring()
        val flow = MutableSharedFlow<DeviceStatus>(extraBufferCapacity = STATUS_FLOW_BUFFER)
        statusFlow = flow
        statusPublisher = StatusPublisher(flow, activeSession, Clock.systemUTC(), dispatcher)
        val reactor = HarnessRingReactor()
        ringReactor = reactor
        ringWatchJob =
            scope.launch {
                activeSession.receive(Channel.CHANNEL_STATUS).collect { envelope ->
                    when (envelope.payloadCase) {
                        Envelope.PayloadCase.RING -> {
                            if (reactor.ring()) {
                                println("EVENT RING_STARTED ${reactor.startCount}")
                            } else {
                                println("EVENT RING_SUPPRESSED")
                            }
                        }
                        Envelope.PayloadCase.RING_STOP -> {
                            if (reactor.ringStopReceived()) {
                                println("EVENT RING_STOPPED ${envelope.ringStop.origin}")
                            }
                        }
                        else -> Unit
                    }
                }
            }
    }

    private fun stopStatusAndRingWiring() {
        statusPublisher?.close()
        statusPublisher = null
        statusFlow = null
        ringWatchJob?.cancel()
        ringWatchJob = null
        ringReactor = null
    }

    /**
     * `STATUS <batteryLevel> <isCharging:0|1> <networkType> <signalLevel>` (E23-08): pushes one
     * `DeviceStatus` value change into the real [StatusPublisher]'s input flow -- exactly like a
     * real battery/network/signal observer emitting a new value (E23-02) -- so the throttle
     * decision of whether/when to actually send it onto the wire is the real E23-03 logic, not
     * this CLI's own. `networkType` is one of `WIFI`, `CELLULAR`, `OFFLINE`, `UNSPECIFIED`
     * (`NetworkType`'s wire names without the `NETWORK_TYPE_` prefix).
     */
    private fun status(argsLine: String) {
        val flow = statusFlow
        if (flow == null) {
            println("ERROR not connected")
            return
        }
        val args = argsLine.split(" ").filter { it.isNotEmpty() }
        if (args.size != STATUS_ARG_COUNT) {
            println("ERROR usage: STATUS <batteryLevel> <isCharging:0|1> <networkType> <signalLevel>")
            return
        }
        val (batteryArg, chargingArg, networkArg, signalArg) = args
        val battery = batteryArg.toIntOrNull()
        val signal = signalArg.toIntOrNull()
        val networkType =
            when (networkArg.uppercase()) {
                "WIFI" -> NetworkType.NETWORK_TYPE_WIFI
                "CELLULAR" -> NetworkType.NETWORK_TYPE_CELLULAR
                "OFFLINE" -> NetworkType.NETWORK_TYPE_OFFLINE
                "UNSPECIFIED" -> NetworkType.NETWORK_TYPE_UNSPECIFIED
                else -> null
            }
        if (battery == null || signal == null || networkType == null || (chargingArg != "0" && chargingArg != "1")) {
            println("ERROR invalid STATUS arguments")
            return
        }
        val value =
            deviceStatus {
                batteryLevel = battery
                isCharging = chargingArg == "1"
                this.networkType = networkType
                signalLevel = signal
            }
        if (flow.tryEmit(value)) {
            println("OK STATUS_QUEUED")
        } else {
            println("ERROR STATUS_QUEUE_FULL")
        }
    }

    /**
     * `INPUTWATCH` (E62-08): routes every `InputEvent` the connected [session] receives on the INPUT
     * channel through a [RemoteInputHarness] (the real `InputGate`, no mirror consent, recording
     * dispatcher); `INPUTSTATS` prints its counts.
     */
    private fun inputWatch() {
        val activeSession = session
        if (activeSession == null) {
            println("ERROR no session open (CONNECT first)")
            return
        }
        val input = RemoteInputHarness()
        remoteInput = input
        inputWatchJob?.cancel()
        inputWatchJob =
            scope.launch {
                activeSession.receive(Channel.CHANNEL_INPUT).collect { envelope ->
                    if (envelope.hasInputEvent()) input.handle(envelope.inputEvent)
                }
            }
        println("OK INPUT_WATCHING")
    }

    /** `RINGSTATE` (E23-08): the harness's current [HarnessRingReactor] counters, for scenario assertions. */
    private fun ringState() {
        val reactor = ringReactor
        if (reactor == null) {
            println("ERROR not connected")
            return
        }
        println("OK RINGING=${reactor.isCurrentlyRinging} STARTS=${reactor.startCount} STOPS=${reactor.stopCount}")
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
                        startStatusAndRingWiring(newSession)
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
                when (envelope.payloadCase) {
                    Envelope.PayloadCase.REVOKE -> {
                        val handler = RevokeHandler(activeSession, peer) { fp -> locallyRevoked += hexOf(fp) }
                        if (handler.handleRevoke()) {
                            println("EVENT REVOKED ${hexOf(peer)}")
                        }
                    }
                    // E20-15 (Android heartbeat responder) isn't implemented anywhere in this
                    // repo yet (no HeartbeatResponder/PeerDead class under android/core or
                    // android/feature) -- without this, the real Mac's own HeartbeatController
                    // (macos/Packages/TandemTransport/.../HeartbeatController.swift,
                    // deadPeerThreshold = 45s) closes any connection that sits idle across one of
                    // E23-08's long throttle-window waits, confirmed by reproducing it directly
                    // (a `MultiplexerClosedException: ... PeerClosed` after ~50s of app-level
                    // silence). Answering every Heartbeat the Mac's own 15s idle-send timer
                    // produces is the minimum slice of E20-15's own acceptance criterion #1 this
                    // harness needs to keep a long-idle session alive; CHANNEL_CONTROL already has
                    // exactly one consumer (this collector), so it lives here rather than as a
                    // second, competing collector on the same channel.
                    Envelope.PayloadCase.HEARTBEAT -> {
                        heartbeatsReceived.incrementAndGet()
                        runCatching { activeSession.send(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} } }
                    }
                    else -> Unit
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
                        deviceInfoProvider,
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
        stopStatusAndRingWiring()
        println("OK DISCONNECTED")
    }

    /**
     * `SENDNOTIFICATIONS <count>` (E30-14): sends [count] `NotificationPosted` frames on NOTIFY
     * over the already-`OK CONNECTED` [session], one per sequence number `1..count`. The
     * notification text carries only that sequence number (never real content, invariant 7); `key`
     * is the sequence number too, so every frame is a distinct notification rather than an update
     * of the same one. Prints `EVENT SENT <sequence> <epochMillis>` immediately before each send --
     * only a sequence number and a timing, matching the Mac harness's own
     * `harness-notification-latency: <sequence> <epochMillis>` log line -- so
     * `tools/harness/integration/e30-14.sh` can correlate the two by sequence number and compute
     * this run's p95 without either side ever logging notification content.
     */
    private fun sendNotifications(countArg: String) {
        val activeSession = session
        if (activeSession == null) {
            println("ERROR no session open (CONNECT first)")
            return
        }
        val count = countArg.trim().toIntOrNull()
        if (count == null || count <= 0) {
            println("ERROR usage: SENDNOTIFICATIONS <count>")
            return
        }
        runBlocking(dispatcher) {
            for (sequence in 1..count) {
                val sentAtEpochMillis = System.currentTimeMillis()
                activeSession.send(Channel.CHANNEL_NOTIFY) {
                    notificationPosted =
                        notificationPosted {
                            key = sequence.toString()
                            packageName = "dev.tandem.harness"
                            appVersionCode = 1
                            title = "e30-14 latency harness"
                            text = sequence.toString()
                        }
                }
                println("EVENT SENT $sequence $sentAtEpochMillis")
            }
        }
        println("OK SENT_ALL $count")
    }

    /**
     * `FLOOD HEARTBEAT|CONTROL <perSecond> <seconds>` (E20-20): an authenticated, Ready [session]
     * floods CONTROL with `Heartbeat`s or well-formed zero-amount `CreditGrant`s (a no-op
     * non-Heartbeat CONTROL frame) at [perSecond], stopping early once a send fails. Prints the
     * frames sent, the `Heartbeat`s received back, and the final connection state.
     */
    private fun flood(argsLine: String) {
        val args = argsLine.split(" ").filter { it.isNotEmpty() }
        val kind = args.getOrNull(0)?.uppercase()
        val perSecond = args.getOrNull(1)?.toIntOrNull()
        val seconds = args.getOrNull(2)?.toIntOrNull()
        val activeSession = session
        if (kind !in setOf("HEARTBEAT", "CONTROL") || perSecond == null || perSecond <= 0 || seconds == null || seconds <= 0) {
            println("ERROR usage: FLOOD HEARTBEAT|CONTROL <perSecond> <seconds>")
            return
        }
        if (activeSession == null) {
            println("ERROR no session open (CONNECT first)")
            return
        }
        heartbeatsReceived.set(0)
        var sent = 0
        runBlocking(dispatcher) {
            val perTick = (perSecond / FLOOD_TICKS_PER_SECOND).coerceAtLeast(1)
            repeat(seconds * FLOOD_TICKS_PER_SECOND) {
                val sentOk =
                    runCatching {
                        repeat(perTick) {
                            activeSession.send(Channel.CHANNEL_CONTROL) {
                                if (kind == "HEARTBEAT") {
                                    heartbeat = heartbeat {}
                                } else {
                                    creditGrant = creditGrant { channel = Channel.CHANNEL_NOTIFY }
                                }
                            }
                            sent++
                        }
                    }.isSuccess
                if (!sentOk) return@runBlocking
                delay(MILLIS_PER_SECOND / FLOOD_TICKS_PER_SECOND)
            }
        }
        println("OK FLOOD SENT=$sent HEARTBEATS_RECEIVED=${heartbeatsReceived.get()} STATE=${activeSession.state.value}")
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
        rawRotationChallenge = null

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
                                    if (envelope.hasRotationChallenge()) {
                                        rawRotationChallenge = envelope.rotationChallenge.challenge.toByteArray()
                                    }
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
        rawRotationChallenge = null
        println("OK RAWCLOSED")
    }

    /**
     * `RAWCHALLENGE` (E70-09): prints the Mac's `RotationChallenge` for the current raw session as
     * `OK CHALLENGE <cbHex>` -- the one [rawOpen] already consumed, or the next one to arrive -- so
     * a scenario can carry it to another session with `RAWROTATE CB=<cbHex>`.
     */
    private fun rawRotationChallengeCommand() {
        val cb = awaitRawRotationChallenge()
        println(if (cb == null) "ERROR NO_CHALLENGE" else "OK CHALLENGE ${cb.toLowerHex()}")
    }

    /**
     * `RAWROTATE [CB=<cbHex>] [HELDKEY]` (E70-09): sends one real `KeyRotation` on the raw session,
     * signed by this process's identity key and a new key over `cb` (the session's own
     * `RotationChallenge` unless `CB=` overrides it -- a replayed `cb` from another session, or any
     * 32 bytes where the Mac never sends one, e.g. a pairing-candidate connection). `HELDKEY` uses
     * the key `RAWKEYGEN` generated as `newSpki` instead of a fresh one. Prints `EVENT
     * ROTATION_ACK`, `EVENT ROTATION_REJECT <reason>`, `EVENT ROTATION_CLOSED` or `EVENT
     * ROTATION_TIMEOUT`.
     */
    private fun rawRotate(argsLine: String) {
        val flags = argsLine.split(" ").filter { it.isNotEmpty() }
        val cbOverride = flags.firstOrNull { it.startsWith("CB=", ignoreCase = true) }?.substringAfter("=")?.decodeHex()
        val useHeldKey = flags.any { it.equals("HELDKEY", ignoreCase = true) }
        val activeSession = rawSession
        val cb = cbOverride ?: awaitRawRotationChallenge()
        if (activeSession == null || cb == null) {
            println("ERROR no raw session open or no RotationChallenge (RAWOPEN first, or pass CB=<hex>)")
            return
        }
        val rotation = runCatching { rawRotation.build(cb, useHeldKey) }.getOrElse {
            println("ERROR ${it.message}")
            return
        }
        runBlocking(dispatcher) {
            activeSession.send(Channel.CHANNEL_CONTROL) { keyRotation = rotation }
        }
        println("OK SENT_ROTATION")
        printRawRotationOutcome(activeSession)
    }

    /**
     * `RAWMACROTATION [ACK|NOACK]` (E70-09): the phone side of a Mac-initiated rotation on the raw
     * session. Sends the unsolicited `RotationChallenge` a phone sends on every control session, waits
     * for the Mac's `KeyRotation` and checks both signatures against the Mac key that authenticated
     * this session. Prints `EVENT MAC_ROTATION_OFFERED <newSpkiFingerprintHex> VERIFIED|INVALID`, or
     * `EVENT MAC_ROTATION_NONE` if no offer arrived. With `ACK` (default `NOACK`) a verified offer is
     * answered with `RotationAck` and `OK ACKED` is printed. Nothing is pinned: a scenario then shows
     * which keys the Mac still presents to a phone that has, or has not, acked.
     */
    private fun rawMacRotation(argsLine: String) {
        val ack = argsLine.trim().equals("ACK", ignoreCase = true)
        val activeSession = rawSession
        val macSpkiDer = rawMacSpkiDer
        if (activeSession == null || macSpkiDer == null) {
            println("ERROR no raw session open (RAWOPEN first)")
            return
        }
        val challenge = RawMacRotation.newChallenge()
        val outcome =
            runBlocking(dispatcher) {
                activeSession.send(Channel.CHANNEL_CONTROL) {
                    rotationChallenge = rotationChallenge { this.challenge = ByteString.copyFrom(challenge) }
                }
                withTimeoutOrNull(RAW_OUTCOME_TIMEOUT_MS) {
                    waitForControlEnvelope(activeSession) { it.hasKeyRotation() }
                }
            }
        val offer = (outcome as? RawWaitOutcome.Success)?.envelope?.keyRotation
        if (offer == null) {
            println("EVENT MAC_ROTATION_NONE")
            return
        }
        val valid = RawMacRotation.isValidOffer(macSpkiDer, challenge, offer)
        println("EVENT MAC_ROTATION_OFFERED ${RawMacRotation.newKeyFingerprintHex(offer)} ${if (valid) "VERIFIED" else "INVALID"}")
        if (ack && valid) {
            runBlocking(dispatcher) { activeSession.send(Channel.CHANNEL_CONTROL) { rotationAck = rotationAck {} } }
            println("OK ACKED")
        }
    }

    /**
     * `RAWTICKET` (E60-05): sends `RequestMediaTicket` on the raw control session and prints the
     * Mac's `MediaTicketGrant` ticket as `OK TICKET <hex>` (`ERROR NO_GRANT` if none arrives), so a
     * scenario can present it on a media connection with `MEDIAOPEN`.
     */
    private fun rawTicket() {
        val activeSession = rawSession
        if (activeSession == null) {
            println("ERROR no raw session open (RAWOPEN first)")
            return
        }
        val outcome =
            runBlocking(dispatcher) {
                activeSession.send(Channel.CHANNEL_CONTROL) { requestMediaTicket = requestMediaTicket { } }
                withTimeoutOrNull(RAW_CHALLENGE_TIMEOUT_MS) {
                    waitForControlEnvelope(activeSession) { it.hasMediaTicketGrant() }
                }
            }
        val ticket = (outcome as? RawWaitOutcome.Success)?.envelope?.mediaTicketGrant?.ticket?.toByteArray()
        println(if (ticket == null) "ERROR NO_GRANT" else "OK TICKET ${ticket.toLowerHex()}")
    }

    /**
     * `MEDIAOPEN <host> <port> <macFpSpkiFingerprintBase64Url> <ticketHex|NONE|SILENT> [HOLD]`
     * (E60-05): dials a second, fully pinned mTLS connection with this process's identity and
     * presents `MediaHello` carrying the given ticket (`NONE`: no ticket; `SILENT`: nothing at all).
     * Prints `OK MEDIA_CONNECTED` once the handshake completed, then `EVENT MEDIA_CLOSED <ms>` when
     * the Mac closed the connection (ms since the handshake) or `EVENT MEDIA_OPEN` if it stayed open
     * for [MEDIA_CLOSE_TIMEOUT_MS]. With `HOLD` the connection is kept open without waiting and
     * `OK MEDIA_HELD` is printed instead. `ERROR HANDSHAKE_REJECTED <reason>` when mTLS failed.
     */
    private fun mediaOpen(argsLine: String) {
        val args = argsLine.split(" ").filter { it.isNotEmpty() }
        val port = args.getOrNull(1)?.toIntOrNull()
        val fingerprintBytes = args.getOrNull(2)?.let { runCatching { Base64.getUrlDecoder().decode(it) }.getOrNull() }
        val presentation = args.getOrNull(3)?.let(RawMedia::parsePresentation)
        if (args.size < MEDIAOPEN_MIN_ARGS || port == null || fingerprintBytes == null || presentation == null) {
            println("ERROR usage: MEDIAOPEN <host> <port> <spkiFingerprintBase64Url> <ticketHex|NONE|SILENT> [HOLD]")
            return
        }
        val factory =
            SslClientFactory(
                keyManager,
                PinningTrustManager(PinSource { listOf(SpkiFingerprint(fingerprintBytes)) }),
                JvmConscryptSessionTicketDisabler(),
            )
        val socket = factory.createSocket().apply { soTimeout = MEDIA_CLOSE_TIMEOUT_MS }
        val stream =
            runCatching { factory.connect(socket, InetAddress.getByName(args[0]), port) }
                .getOrElse {
                    println("ERROR HANDSHAKE_REJECTED ${it.message}")
                    return
                }
        println("OK MEDIA_CONNECTED")
        val startNanos = System.nanoTime()
        val hello =
            when (presentation) {
                MediaPresentation.NoTicket -> RawMedia.helloFrame(null)
                MediaPresentation.Silent -> null
                is MediaPresentation.Ticket -> RawMedia.helloFrame(presentation.bytes)
            }
        runCatching {
            if (hello != null) {
                stream.output.write(hello)
                stream.output.flush()
            }
        }
        if (args.drop(MEDIAOPEN_MIN_ARGS).any { it.equals("HOLD", ignoreCase = true) }) {
            heldMediaStreams += stream
            println("OK MEDIA_HELD")
            return
        }
        val closed =
            try {
                stream.input.read()
                true
            } catch (_: SocketTimeoutException) {
                false
            } catch (_: IOException) {
                true
            }
        stream.closeAbruptly()
        println(if (closed) "EVENT MEDIA_CLOSED ${(System.nanoTime() - startNanos) / NANOS_PER_MILLI}" else "EVENT MEDIA_OPEN")
    }

    private fun awaitRawRotationChallenge(): ByteArray? {
        rawRotationChallenge?.let { return it }
        val activeSession = rawSession ?: return null
        val outcome =
            runBlocking(dispatcher) {
                withTimeoutOrNull(RAW_CHALLENGE_TIMEOUT_MS) {
                    waitForControlEnvelope(activeSession) { it.hasRotationChallenge() }
                }
            }
        val cb = (outcome as? RawWaitOutcome.Success)?.envelope?.rotationChallenge?.challenge?.toByteArray()
        rawRotationChallenge = cb
        return cb
    }

    private fun printRawRotationOutcome(activeSession: TandemSession) {
        val outcome =
            runBlocking(dispatcher) {
                withTimeoutOrNull(RAW_OUTCOME_TIMEOUT_MS) {
                    waitForControlEnvelope(activeSession) { it.hasRotationAck() || it.hasRotationReject() }
                }
            }
        when (outcome) {
            null, RawWaitOutcome.TimedOut -> println("EVENT ROTATION_TIMEOUT")
            RawWaitOutcome.ConnectionLost -> println("EVENT ROTATION_CLOSED")
            is RawWaitOutcome.Success ->
                if (outcome.envelope.hasRotationAck()) {
                    println("EVENT ROTATION_ACK")
                } else {
                    println("EVENT ROTATION_REJECT ${outcome.envelope.rotationReject.reason.rejectName()}")
                }
        }
    }

    private fun RotationRejectReason.rejectName(): String = name.removePrefix("ROTATION_REJECT_REASON_")

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
        const val MEDIAOPEN_MIN_ARGS = 4
        const val STATUS_ARG_COUNT = 4
        const val STATUS_FLOW_BUFFER = 64
    }
}

/**
 * Non-hardware-identifying device info for this JVM harness process (E14-06). `displayName`
 * defaults to [DEFAULT_DISPLAY_NAME] but is overridable via `--display-name` (E15-07): the canary
 * procedure's Phase 1 step feeds a fresh `TANDEM-CANARY-<random>` string through this same
 * production [DeviceInfoProvider] so it rides `PairRequest.deviceInfo.displayName` during a real
 * pairing -- no test-only wire payload or debug channel exists for canary injection.
 */
private class HarnessDeviceInfoProvider(
    private val displayName: String,
) : DeviceInfoProvider {
    override fun displayName(): String = displayName

    override fun model(): String = "jvm-client"

    companion object {
        const val DEFAULT_DISPLAY_NAME = "JVM Harness Client"
    }
}
