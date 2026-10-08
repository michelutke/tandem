package dev.tandem.feature.files

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TransferBatchAggregatorTest {
    private fun percent(bytes: TransferBytes?) = bytes!!.transferred * 100 / bytes.total

    @Test
    fun aggregator_firstOfTwoFilesCompletes_percentDoesNotDrop() {
        val aggregator = TransferBatchAggregator()
        val before =
            aggregator.update(
                emptyMap(),
                mapOf("a" to TransferBytes(100, 100), "b" to TransferBytes(0, 100)),
            )

        val after = aggregator.update(emptyMap(), mapOf("b" to TransferBytes(10, 100)))

        assertEquals(50, percent(before.receiving))
        assertTrue(percent(after.receiving) >= percent(before.receiving))
        assertEquals(55, percent(after.receiving))
    }

    @Test
    fun aggregator_allFinished_resetsForNextBatch() {
        val aggregator = TransferBatchAggregator()
        aggregator.update(mapOf("a" to TransferBytes(50, 100)), emptyMap())
        aggregator.update(mapOf("b" to TransferBytes(10, 100)), emptyMap())

        assertNull(aggregator.update(emptyMap(), emptyMap()).sending)

        assertEquals(10, percent(aggregator.update(mapOf("c" to TransferBytes(10, 100)), emptyMap()).sending))
    }
}
