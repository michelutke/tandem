package dev.tandem.feature.mirror

/** Seam over launching the system MediaProjection consent dialog (E61-02). */
fun interface ProjectionConsentLauncher {
    fun launchConsent()
}
