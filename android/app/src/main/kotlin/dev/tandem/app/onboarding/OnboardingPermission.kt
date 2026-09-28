package dev.tandem.app.onboarding

/**
 * The two permissions [OnboardingViewModel.allow] can request through [PermissionRequester]
 * (E20-14). A closed set by design: battery-optimization and CAMERA each already have their own
 * request path ([dev.tandem.app.onboarding.BatteryOnboardingScreen],
 * [dev.tandem.feature.pairing.scan.ScannerScreen]), and later features (SMS, contacts, phone,
 * media, accessibility, notification policy) are never requested during onboarding at all.
 */
enum class OnboardingPermission {
    NOTIFICATION_LISTENER,
    POST_NOTIFICATIONS,
}
