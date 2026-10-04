package dev.tandem.feature.input

interface NotificationPresenter {
    fun post(): Boolean

    fun remove()

    /** True only while the notification is actually still posted, so a dismissal is noticed. */
    fun isPosted(): Boolean
}

interface OverlayBadge {
    fun attach(): Boolean

    fun detach()

    fun isAttached(): Boolean
}

/**
 * The invariant 8 on-phone indicator: an ongoing notification plus an accessibility-overlay badge.
 * It is showing only while both are live; either one disappearing closes the input gate.
 */
class RemoteInputIndicator(
    private val notification: NotificationPresenter,
    private val overlay: OverlayBadge,
) {
    fun show(): Boolean {
        if (notification.post() && overlay.attach()) return true
        hide()
        return false
    }

    fun hide() {
        overlay.detach()
        notification.remove()
    }

    fun isShowing(): Boolean = notification.isPosted() && overlay.isAttached()
}

class IndicatorGateState(
    private val indicator: RemoteInputIndicator,
    private val mediaActive: () -> Boolean,
    private val currentPeer: () -> String?,
) : LiveGateState {
    override fun mediaActive(): Boolean = mediaActive.invoke()

    override fun currentPeer(): String? = currentPeer.invoke()

    override fun indicatorShowing(): Boolean = indicator.isShowing()
}
