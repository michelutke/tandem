package dev.tandem.app.onboarding

/**
 * The onboarding sequence's fixed step order (E20-14, F-4.1, F-1.1, UC-02): identity bootstrap,
 * notification-listener access, POST_NOTIFICATIONS (API 33+ only), unrestricted battery (E20-04),
 * then Scan Mac QR (E14-10). [IDENTITY] has no screen of its own -- it runs silently before any
 * onboarding UI shows (E10-04) -- every other step has a Composable screen in this package.
 *
 * Later features (SMS, contacts, phone, media, accessibility, notification policy) are
 * deliberately absent: they ask lazily from their own future epics, never during onboarding.
 */
enum class OnboardingStep {
    IDENTITY,
    NOTIFICATION_LISTENER,
    POST_NOTIFICATIONS,
    BATTERY,
    SCAN_QR,
}
