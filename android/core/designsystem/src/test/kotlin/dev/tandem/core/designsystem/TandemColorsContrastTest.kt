package dev.tandem.core.designsystem

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E00-31 acceptance: "Colour contrast of ink2 on paper is >= 4.5:1". Framework-free JUnit5 test;
// androidx.compose.ui.graphics.Color is plain host-JVM code, so no Robolectric is needed here.
class TandemColorsContrastTest {
    @Test
    fun tandemColors_ink2OnPaper_contrastAtLeast4point5() {
        val contrast = TandemColors.contrastRatio(TandemColors.ink2, TandemColors.paper)

        assertTrue(contrast >= 4.5, "expected ink2 on paper contrast >= 4.5:1, was $contrast:1")
    }
}
