package com.tandem.spike.keystoresslsocket

import androidx.test.platform.app.InstrumentationRegistry

/**
 * Instrumentation arguments (`adb shell am instrument -e <key> <value> ...`) so the same APK can
 * be pointed at whichever host openssl s_server ports the driving shell script started, and so
 * the SPKI pin (computed from the freshly generated server cert on each run) never has to be
 * baked into source.
 */
object SpikeArgs {
    private val args get() = InstrumentationRegistry.getArguments()

    val host: String get() = args.getString("host") ?: "10.0.2.2"
    val mainPort: Int get() = requireNotNull(args.getString("mainPort")).toInt()
    val tls12Port: Int get() = requireNotNull(args.getString("tls12Port")).toInt()
    val exporterPort: Int get() = requireNotNull(args.getString("exporterPort")).toInt()
    val expectedPinHex: String get() = requireNotNull(args.getString("expectedPin"))
}
