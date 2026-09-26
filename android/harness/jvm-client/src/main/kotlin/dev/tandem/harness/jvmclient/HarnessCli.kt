package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.SpkiFingerprint
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File
import java.net.InetAddress
import java.time.Clock
import java.util.Base64
import java.util.concurrent.Executors

private const val DEFAULT_IDENTITY_FILE = "harness-identity.bin"

/**
 * Entry point (E15-21): a single-threaded stdin/stdout CLI wired to the real `core/crypto`,
 * `core/transport` and `core/pairing` modules. `--identity-file <path>` selects where the
 * process's [PersistentIdentityKeyStore] persists its identity (default: [DEFAULT_IDENTITY_FILE]
 * in the current working directory) so a restarted process reloads the same key. Reads one
 * command per line from stdin until `EXIT` or end of input.
 */
fun main(args: Array<String>) {
    HarnessConscryptProvider.ensureInstalled()
    val identityFile = File(argValue(args, "--identity-file") ?: DEFAULT_IDENTITY_FILE)
    val executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "harness-cli") }
    val dispatcher = executor.asCoroutineDispatcher()
    val scope = CoroutineScope(SupervisorJob() + dispatcher)

    val identityKeyStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
    identityKeyStore.getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)
    val keyManager = IdentityKeyManager(identityKeyStore, PersistentIdentityKeyStore.IDENTITY_ALIAS)

    val cli = HarnessCli(keyManager, dispatcher, scope)
    try {
        while (true) {
            val line = readlnOrNull() ?: break
            if (line.isBlank()) continue
            if (!cli.handle(line.trim())) break
        }
    } finally {
        cli.shutdown()
        executor.shutdownNow()
    }
}

private fun argValue(
    args: Array<String>,
    name: String,
): String? {
    val index = args.indexOf(name)
    return if (index >= 0 && index + 1 < args.size) args[index + 1] else null
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
                    PairingStateMachine(Clock.systemUTC(), dispatcher, connector, trustCommitter, result.invite)
                pairing = machine
                scope.launch { machine.state.collect { println("EVENT $it") } }
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
