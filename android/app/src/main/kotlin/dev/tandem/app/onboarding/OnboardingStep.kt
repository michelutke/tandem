package dev.tandem.app.onboarding

/**
 * The onboarding sequence's fixed step order (F-4.1, F-1.1, UC-02, ui-spec §7.2): identity
 * bootstrap, the welcome screen, the permissions screen, then Scan Mac QR (E14-10). [IDENTITY] has
 * no screen of its own -- it runs silently before any onboarding UI shows (E10-04).
 *
 * Features not listed on the permissions screen (media, accessibility, notification policy) ask
 * lazily from their own epics, never during onboarding.
 */
enum class OnboardingStep {
    IDENTITY,
    WELCOME,
    PERMISSIONS,
    SCAN_QR,
}
