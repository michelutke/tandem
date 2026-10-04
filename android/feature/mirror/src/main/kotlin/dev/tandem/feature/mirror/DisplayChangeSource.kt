package dev.tandem.feature.mirror

import dev.tandem.protocol.v1.Orientation

/** Real display size in pixels after the change, and its rotation. */
data class DisplayGeometry(
    val widthPx: Int,
    val heightPx: Int,
    val orientation: Orientation,
)

/** The display-change seam (E61-05): the real adapter wraps a `DisplayManager.DisplayListener`. */
interface DisplayChangeSource {
    fun start(listener: (DisplayGeometry) -> Unit)

    fun stop()
}

object NoDisplayChanges : DisplayChangeSource {
    override fun start(listener: (DisplayGeometry) -> Unit) = Unit

    override fun stop() = Unit
}
