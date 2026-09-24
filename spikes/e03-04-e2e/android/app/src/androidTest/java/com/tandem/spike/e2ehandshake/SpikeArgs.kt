package com.tandem.spike.e2ehandshake

import androidx.test.platform.app.InstrumentationRegistry

/**
 * Instrumentation arguments (`adb shell am instrument -e <key> <value> ...`) so the same APK can
 * be pointed at whichever port the real macOS `e2e-mac` listener (E03-01 spike, wired for E03-04)
 * is bound to on this run, and so the Mac server's SPKI pin (computed from its freshly generated
 * identity on each run) never has to be baked into source.
 */
object SpikeArgs {
    private val args get() = InstrumentationRegistry.getArguments()

    val host: String get() = args.getString("host") ?: "10.0.2.2"
    val port: Int get() = requireNotNull(args.getString("port")).toInt()
    val expectedServerPinHex: String get() = requireNotNull(args.getString("expectedServerPin"))
}
