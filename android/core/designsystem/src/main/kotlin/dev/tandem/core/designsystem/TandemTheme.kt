package dev.tandem.core.designsystem

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily

/**
 * Tandem's M3 theme (ui-spec.md §3, §5.2): screens must read colour and type through this theme
 * (or `TandemColors` / `TandemType` directly), never literal values (E00-31 acceptance). Android
 * maps the tokens onto a Material 3 colour scheme but never applies dynamic colour to
 * `signal` / `alert` (ui-spec §3.1).
 * Built on `MaterialExpressiveTheme` (D-81) with the expressive motion scheme, so the M3E components
 * (floating toolbar, loading indicator, button groups) pick up expressive springs and shapes.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
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
        Typography().withFontFamily(InterTightFontFamily).copy(
            titleLarge = TandemType.titleEmphasis,
            titleMedium = TandemType.rowTitle,
            bodyLarge = TandemType.body,
            bodyMedium = TandemType.body,
            labelSmall = TandemType.meta,
        )
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        motionScheme = MotionScheme.expressive(),
        typography = typography,
        content = content,
    )
}

private fun Typography.withFontFamily(fontFamily: FontFamily) =
    copy(
        displayLarge = displayLarge.copy(fontFamily = fontFamily),
        displayMedium = displayMedium.copy(fontFamily = fontFamily),
        displaySmall = displaySmall.copy(fontFamily = fontFamily),
        headlineLarge = headlineLarge.copy(fontFamily = fontFamily),
        headlineMedium = headlineMedium.copy(fontFamily = fontFamily),
        headlineSmall = headlineSmall.copy(fontFamily = fontFamily),
        titleLarge = titleLarge.copy(fontFamily = fontFamily),
        titleMedium = titleMedium.copy(fontFamily = fontFamily),
        titleSmall = titleSmall.copy(fontFamily = fontFamily),
        bodyLarge = bodyLarge.copy(fontFamily = fontFamily),
        bodyMedium = bodyMedium.copy(fontFamily = fontFamily),
        bodySmall = bodySmall.copy(fontFamily = fontFamily),
        labelLarge = labelLarge.copy(fontFamily = fontFamily),
        labelMedium = labelMedium.copy(fontFamily = fontFamily),
        labelSmall = labelSmall.copy(fontFamily = fontFamily),
    )
