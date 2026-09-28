package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.pairing.DeviceInfoProvider
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.PairingStateMachine
import dev.tandem.core.pairing.TrustCommitter
import dev.tandem.core.pairing.qr.ParseInviteResult
import dev.tandem.core.pairing.qr.QrPayloadParser
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.tls.SslClientFactory
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

    val cli = HarnessCli(keyManager, dispatcher, scope)
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
    val hex = fingerprint.bytes.joinToString(separator = "") { "%02x".format(it) }
    println("harness-identity-spki: $hex")
}

/** Holds the CLI's session/pairing state across commands; see [main] for how it is wired up. */
private class HarnessCli(
    private val keyManager: IdentityKeyManager,
    private val dispatcher: CoroutineDispatcher,
    private val scope: CoroutineScope,
) {
    private var session: TandemSession? = null
    private var pairing: PairingStateMachine? = null

    /** Handles one command line; returns `false` if the CLI should stop reading further commands. */
    fun handle(line: String): Boolean {
        val parts = line.split(" ", limit = 2)
        val command = parts[0].uppercase()
        val rest = parts.getOrElse(1) { "" }
        when (command) {
            "CONNECT" -> connect(rest)
            "PAIR" -> pair(rest)
            "CONFIRM" -> confirm()
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

        runCatching {
            val pinSource = PinSource { listOf(SpkiFingerprint(fingerprintBytes)) }
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
                        println("OK CONNECTED")
                    }
                    is ConnectionState.Failed -> println("ERROR ${outcome.reason}")
                    else -> Unit
                }
            }
        }.onFailure { println("ERROR ${it.message}") }
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
