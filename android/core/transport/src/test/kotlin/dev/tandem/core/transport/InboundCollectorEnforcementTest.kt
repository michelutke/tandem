package dev.tandem.core.transport

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * E20-22: [ChannelDispatcher] must be the only collector of a multiplexer's single-consumer inbound
 * flows, so no production code may call `ChannelMultiplexer.inbound(...)` anywhere else (the
 * handshake's own pre-Ready CONTROL read is the one allowed exception; the dispatcher waits for
 * Ready before reading).
 */
class InboundCollectorEnforcementTest {
    private val androidRoot = File("..").canonicalFile.parentFile

    @Test
    fun productionSources_multiplexerInbound_onlyCalledByDispatcherWiringAndHandshake() {
        val mainSources =
            androidRoot
                .walkTopDown()
                .onEnter { it.name != "build" }
                .filter { it.isFile && it.extension == "kt" && "/src/main/" in it.path }
                .toList()
        assertTrue(mainSources.isNotEmpty(), "no production sources found under $androidRoot")

        val callers =
            mainSources
                .filter { Regex("""\.inbound\(""").containsMatchIn(it.readText()) }
                .map { it.name }
                .sorted()

        assertEquals(listOf("ByteStreamSession.kt", "VersionHandshake.kt"), callers)
    }
}
