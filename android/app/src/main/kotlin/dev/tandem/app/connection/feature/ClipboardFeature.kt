package dev.tandem.app.connection.feature

import dev.tandem.app.clipboard.ClipboardWriter
import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.clipboard.LiveClipboardSession

/** Writes incoming CLIPBOARD frames locally and exposes the session to the send entry points (F-6.1). */
class ClipboardFeature(
    private val clipboardWriter: ClipboardWriter,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
    ) {
        LiveClipboardSession.current = session
        try {
            clipboardWriter.start(session)
        } finally {
            if (LiveClipboardSession.current === session) LiveClipboardSession.current = null
        }
    }
}
