package dev.tandem.app.mirror

import dev.tandem.feature.input.Size
import dev.tandem.feature.mirror.CaptureSource
import dev.tandem.feature.mirror.DisplayChangeSource
import dev.tandem.feature.mirror.EncoderFactory
import dev.tandem.feature.mirror.ProjectionConsentLauncher

enum class MirrorFailure { PinMismatch, Unreachable }

/** Android-facing seams of one mirror round; the real implementation is [AndroidMirrorPlatform]. */
interface MirrorPlatform {
    val consentLauncher: ProjectionConsentLauncher

    /** Receives the system MediaProjection consent outcome; null stops listening. */
    fun setConsentListener(listener: ((granted: Boolean) -> Unit)?)

    fun displaySize(): Size

    fun encoderFactory(): EncoderFactory

    fun displayChanges(): DisplayChangeSource

    /** Starts the `mediaProjection` foreground service and returns once it is foreground (false on timeout). */
    suspend fun startCaptureService(): Boolean

    fun stopCaptureService()

    /** Turns the granted consent into a capture of [width] x [height]; consumed once. Null when none is held. */
    fun openCapture(
        width: Int,
        height: Int,
    ): CaptureSource?

    /** Shows the visible fail-closed error (invariant 5). */
    fun showFailure(failure: MirrorFailure)
}
