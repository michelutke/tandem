package dev.tandem.core.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/**
 * Tandem's M3 theme (ui-spec.md §3, §5.2): screens must read colour and type through this theme
 * (or `TandemColors` / `TandemType` directly), never literal values (E00-31 acceptance). Android
 * maps the tokens onto a Material 3 colour scheme but never applies dynamic colour to
 * `signal` / `alert` (ui-spec §3.1).
 *
 * Deviation: `androidx.compose.material3.MaterialExpressiveTheme` exists in the pinned material3
 * 1.4.0 build but is declared `internal` there (not part of its public API surface yet), so this
 * uses the stable `MaterialTheme` instead; switch to `MaterialExpressiveTheme` once a material3
 * release exposes it publicly.
 */
@Composable
fun TandemTheme(content: @Composable () -> Unit) {
    val colorScheme =
        lightColorScheme(
            primary = TandemColors.ink,
            onPrimary = TandemColors.paper,
            secondary = TandemColors.signal,
            onSecondary = TandemColors.paper,
            error = TandemColors.alert,
            onError = TandemColors.paper,
            background = TandemColors.paper,
            onBackground = TandemColors.ink,
            surface = TandemColors.paper,
            onSurface = TandemColors.ink,
            onSurfaceVariant = TandemColors.ink2,
            outline = TandemColors.line,
            outlineVariant = TandemColors.lineUnlitDot,
        )
    val typography =
        Typography(
            titleLarge = TandemType.titleEmphasis,
            titleMedium = TandemType.rowTitle,
            bodyLarge = TandemType.body,
            bodyMedium = TandemType.body,
            labelSmall = TandemType.meta,
        )
    MaterialTheme(
        colorScheme = colorScheme,
        typography = typography,
        content = content,
    )
}
