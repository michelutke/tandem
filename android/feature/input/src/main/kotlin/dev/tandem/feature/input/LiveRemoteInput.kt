package dev.tandem.feature.input

/** What a connected [TandemAccessibilityService] offers the per-session composition in `:app`. */
class RemoteInputTarget(
    val handler: InputActionHandler,
    val translator: GestureTranslator,
    val indicator: RemoteInputIndicator,
)

/** Process-wide slot for the framework-constructed [TandemAccessibilityService]'s [RemoteInputTarget]. */
object LiveRemoteInput {
    @Volatile
    var current: RemoteInputTarget? = null
}
