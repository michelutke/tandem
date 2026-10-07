package dev.tandem.app.activity

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.LocalDate

// E20-18 tdd:
//   ui: activityChart_sevenDays_rendersSevenColumns
@RunWith(AndroidJUnit4::class)
class ActivityScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun activityChart_sevenDays_rendersSevenColumns() {
        val entries =
            listOf(
                ActivityEntry(ActivityEventType.FileReceived, 2048, null, Instant.parse("2026-01-10T09:00:00Z")),
                ActivityEntry(ActivityEventType.ClipboardFromMac, null, null, Instant.parse("2026-01-09T09:00:00Z")),
            )
        composeRule.setContent {
            ActivityScreen(
                entries = entries,
                today = LocalDate.parse("2026-01-10"),
            )
        }

        composeRule.onNodeWithText("Last 7 days.").assertExists()
        composeRule.onNodeWithText("File received").assertExists()
        val columns = ActivityChartData.from(entries, LocalDate.parse("2026-01-10"))
        assert(columns.values.size == 7 && columns.labels.size == 7)
        assert(columns.values.last() == 1 && columns.values[5] == 1)
        composeRule.onNodeWithContentDescription("S: 1", substring = true).assertExists()
    }
}
