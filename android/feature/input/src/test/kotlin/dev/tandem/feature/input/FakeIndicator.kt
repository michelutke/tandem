package dev.tandem.feature.input

class FakeNotificationPresenter : NotificationPresenter {
    var posted = false
    var postSucceeds = true

    override fun post(): Boolean {
        posted = postSucceeds
        return posted
    }

    override fun remove() {
        posted = false
    }

    override fun isPosted(): Boolean = posted
}

class FakeOverlayBadge : OverlayBadge {
    var attached = false
    var attachSucceeds = true

    override fun attach(): Boolean {
        attached = attachSucceeds
        return attached
    }

    override fun detach() {
        attached = false
    }

    override fun isAttached(): Boolean = attached
}
