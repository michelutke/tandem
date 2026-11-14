package dev.tandem.app.connection

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class RePairNoticeStoreTest {
    @Test
    fun rePairNoticeStore_freshFile_notRequired(
        @TempDir directory: File,
    ) {
        assertFalse(RePairNoticeStore(File(directory, "notice")).required.value)
    }

    @Test
    fun rePairNoticeStore_requireThenNewInstance_stillRequiredUntilCleared(
        @TempDir directory: File,
    ) {
        val file = File(directory, "notice")
        RePairNoticeStore(file).require()

        val reopened = RePairNoticeStore(file)
        assertTrue(reopened.required.value)

        reopened.clear()

        assertFalse(reopened.required.value)
        assertFalse(RePairNoticeStore(file).required.value)
    }
}
