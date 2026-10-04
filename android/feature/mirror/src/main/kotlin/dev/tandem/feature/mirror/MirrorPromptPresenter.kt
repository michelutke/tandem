package dev.tandem.feature.mirror

/** Seam over the on-phone mirror start prompt (E61-16); Robolectric-tested via [NotificationMirrorPromptPresenter]. */
interface MirrorPromptPresenter {
    fun show(peerName: String)

    fun remove()
}
