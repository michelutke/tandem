package dev.tandem.feature.input

import dev.tandem.protocol.v1.scroll
import dev.tandem.protocol.v1.swipe
import dev.tandem.protocol.v1.tap
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** GestureTranslator E62-04 tests (`docs/planning/backlog/phase-6.yaml` E62-04's `tdd:` list). Plain JUnit5. */
class GestureTranslatorTest {
    private val actions = FakeAccessibilityActions()
    private val translator = GestureTranslator(actions)
    private val display = Size(1080, 2400)
    private val window = Size(540, 1200)

    @Test
    fun gestureTranslator_tap_singlePointStrokeOf50ms() {
        val result =
            translator.handle(
                tap {
                    x = 270
                    y = 600
                },
                window,
                display,
            )

        assertEquals(InputResult.Performed, result)
        assertEquals(listOf(GestureStroke(540f, 1200f, 540f, 1200f, 50L)), actions.strokes)
    }

    @Test
    fun gestureTranslator_swipe_strokeFromStartToEndOverDuration() {
        val result =
            translator.handle(
                swipe {
                    x1 = 100
                    y1 = 200
                    x2 = 300
                    y2 = 800
                    durationMs = 400
                },
                window,
                display,
            )

        assertEquals(InputResult.Performed, result)
        assertEquals(listOf(GestureStroke(200f, 400f, 600f, 1600f, 400L)), actions.strokes)
    }

    @Test
    fun gestureTranslator_scrollPositiveDy_strokeMovesUpwardFromAnchor() {
        val result =
            translator.handle(
                scroll {
                    x = 270
                    y = 600
                    dx = 0
                    dy = 100
                },
                window,
                display,
            )

        assertEquals(InputResult.Performed, result)
        val stroke = actions.strokes.single()
        assertEquals(540f, stroke.startX)
        assertEquals(1200f, stroke.startY)
        assertEquals(540f, stroke.endX)
        assertEquals(1000f, stroke.endY)
    }

    @Test
    fun gestureTranslator_droppedMapping_noGestureDispatched() {
        val outside =
            translator.handle(
                tap {
                    x = 540
                    y = 600
                },
                window,
                display,
            )
        val invalidSize =
            translator.handle(
                tap {
                    x = 1
                    y = 1
                },
                Size(0, 0),
                display,
            )
        val swipeEndOutside =
            translator.handle(
                swipe {
                    x1 = 10
                    y1 = 10
                    x2 = 9999
                    y2 = 10
                    durationMs = 100
                },
                window,
                display,
            )

        assertEquals(InputResult.NoOp, outside)
        assertEquals(InputResult.NoOp, invalidSize)
        assertEquals(InputResult.NoOp, swipeEndOutside)
        assertEquals(emptyList<GestureStroke>(), actions.strokes)
    }
}
