package dev.tandem.feature.mirror

/**
 * Drives the per-session MediaProjection consent (E61-02). The consent dialog is only launched
 * from [onLocalStartAction], the phone-side user action invariant 8's on-phone indicator protects;
 * every session start launches it again, so a prior grant is never reused (Android 14+).
 */
class MirrorSessionStarter(
    private val consentLauncher: ProjectionConsentLauncher,
) {
    var state: MirrorSessionState = MirrorSessionState.NotStarted
        private set

    fun onLocalStartAction() {
        if (state == MirrorSessionState.AwaitingConsent) return
        state = MirrorSessionState.AwaitingConsent
        consentLauncher.launchConsent()
    }

    fun onConsentResult(granted: Boolean) {
        if (state != MirrorSessionState.AwaitingConsent) return
        state = if (granted) MirrorSessionState.ConsentGranted else MirrorSessionState.NotStarted
    }
}
