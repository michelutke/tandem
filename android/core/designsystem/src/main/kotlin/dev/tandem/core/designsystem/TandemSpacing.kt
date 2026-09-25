package dev.tandem.core.designsystem

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/** 4 dp grid (ui-spec.md §3.3). Screens must use these instead of literal `.dp` values. */
object TandemSpacing {
    val grid = 4.dp
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val xxl = 24.dp

    val screenPadding = 24.dp
    val rowVerticalPadding = 16.dp
}

/** Corner radii (ui-spec.md §3.3): buttons full pill at 32 dp, sheets/dialogs 32–36 dp. */
object TandemRadii {
    val button = 32.dp
    val sheet = 32.dp
    val dialog = 36.dp
}

object TandemShapes {
    val button: Shape = RoundedCornerShape(TandemRadii.button)
    val sheet: Shape = RoundedCornerShape(topStart = TandemRadii.sheet, topEnd = TandemRadii.sheet)
    val dialog: Shape = RoundedCornerShape(TandemRadii.dialog)
    val pill: Shape = RoundedCornerShape(percent = 50)
}
