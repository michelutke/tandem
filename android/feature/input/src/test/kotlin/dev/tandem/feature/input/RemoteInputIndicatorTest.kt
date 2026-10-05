package dev.tandem.feature.input

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class RemoteInputIndicatorTest {
    private val notification = FakeNotificationPresenter()
    private val overlay = FakeOverlayBadge()
    private val indicator = RemoteInputIndicator(notification, overlay)

    @Test
    fun remoteInputIndicator_beforeShow_notShowing() {
        assertFalse(indicator.isShowing())
    }

    @Test
    fun remoteInputIndicator_show_postsNotificationAndAttachesOverlay() {
        assertTrue(indicator.show())
        assertTrue(notification.posted)
        assertTrue(overlay.attached)
        assertTrue(indicator.isShowing())
    }

    @Test
    fun remoteInputIndicator_overlayAttachFails_removesNotificationAndReportsNotShowing() {
        overlay.attachSucceeds = false
        assertFalse(indicator.show())
        assertFalse(notification.posted)
        assertFalse(indicator.isShowing())
    }

    @Test
    fun remoteInputIndicator_notificationPostFails_notShowing() {
        notification.postSucceeds = false
        assertFalse(indicator.show())
        assertFalse(overlay.attached)
    }

    @Test
    fun remoteInputIndicator_hide_removesBoth() {
        indicator.show()
        indicator.hide()
        assertFalse(notification.posted)
        assertFalse(overlay.attached)
        assertFalse(indicator.isShowing())
    }

    @Test
    fun remoteInputIndicator_either_missing_notShowing() {
        indicator.show()
        overlay.attached = false
        assertFalse(indicator.isShowing())
        overlay.attached = true
        notification.posted = false
        assertFalse(indicator.isShowing())
    }

    @Test
    fun indicatorGateState_delegatesToSources() {
        indicator.show()
        val state = IndicatorGateState(indicator, { false }, { null })
        assertFalse(state.mediaActive())
        assertEquals(null, state.currentPeer())
        assertTrue(state.indicatorShowing())
    }
}
