package dev.tandem.feature.input

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** CoordinateMapper E62-03 tests (`docs/planning/backlog/phase-6.yaml` E62-03's `tdd:` list). Plain JUnit5. */
class CoordinateMapperTest {
    private companion object {
        val LANDSCAPE = Size(2400, 1080)
    }

    private fun map(
        x: Float,
        y: Float,
        window: Size,
        display: Size = Size(1080, 2400),
        rotationDelta: RotationDelta = RotationDelta.None,
    ): MappingResult = CoordinateMapper.map(x, y, window, display, rotationDelta)

    @Test
    fun coordinateMapper_portraitWindowMatchingAspect_scalesToDevicePixels() {
        assertEquals(Mapped(540f, 1200f), map(270f, 600f, Size(540, 1200)))
    }

    @Test
    fun coordinateMapper_pillarboxedWindow_subtractsHorizontalOffset() {
        assertEquals(Mapped(0f, 0f), map(275f, 0f, Size(1000, 1000)))
        assertEquals(Mapped(540f, 1200f), map(500f, 500f, Size(1000, 1000)))
    }

    @Test
    fun coordinateMapper_letterboxedLandscapeStream_subtractsVerticalOffset() {
        assertEquals(Mapped(1200f, 0f), map(500f, 275f, Size(1000, 1000), LANDSCAPE))
    }

    @Test
    fun coordinateMapper_pointInLetterboxBar_returnsDropped() {
        assertEquals(Dropped(DropReason.OutsideContent), map(100f, 500f, Size(1000, 1000)))
        assertEquals(Dropped(DropReason.OutsideContent), map(500f, 100f, Size(1000, 1000), LANDSCAPE))
    }

    @Test
    fun coordinateMapper_pointOutsideWindow_returnsDropped() {
        assertEquals(Dropped(DropReason.OutsideWindow), map(-1f, 10f, Size(540, 1200)))
        assertEquals(Dropped(DropReason.OutsideWindow), map(541f, 10f, Size(540, 1200)))
        assertEquals(Dropped(DropReason.OutsideWindow), map(10f, 1201f, Size(540, 1200)))
    }

    @Test
    fun coordinateMapper_rotationDelta90_mapsPoint100x200To200x980() {
        assertEquals(Mapped(200f, 980f), map(100f, 200f, Size(1080, 2400), rotationDelta = RotationDelta.Rotate90))
    }

    @Test
    fun coordinateMapper_rotationDelta180_mapsPoint100x200To980x2200() {
        assertEquals(Mapped(980f, 2200f), map(100f, 200f, Size(1080, 2400), rotationDelta = RotationDelta.Rotate180))
    }

    @Test
    fun coordinateMapper_rotationDelta270_mapsPoint100x200To2200x100() {
        assertEquals(Mapped(2200f, 100f), map(100f, 200f, Size(1080, 2400), rotationDelta = RotationDelta.Rotate270))
    }

    @Test
    fun coordinateMapper_zeroWindowSize_returnsDropped() {
        assertEquals(Dropped(DropReason.InvalidSize), map(0f, 0f, Size(0, 1200)))
        assertEquals(Dropped(DropReason.InvalidSize), map(0f, 0f, Size(540, 0)))
        assertEquals(Dropped(DropReason.InvalidSize), map(0f, 0f, Size(540, 1200), display = Size(0, 2400)))
    }
}
