package dev.tandem.feature.messaging

/** About a third of the 1 MiB envelope limit, so threads plus messages of one response always fit one frame. */
internal const val PAGE_BYTE_BUDGET = 384 * 1024

/** The longest prefix of this list whose items total at most [budget] bytes, but never fewer than one item. */
internal fun <T> List<T>.takeWithinBytes(
    budget: Int,
    sizeOf: (T) -> Int,
): List<T> {
    var bytes = 0
    val fitting = takeWhile { item -> (bytes + sizeOf(item) <= budget).also { if (it) bytes += sizeOf(item) } }
    return fitting.ifEmpty { take(1) }
}

/** This list split into consecutive chunks of at most [budget] bytes each; one empty chunk if it is empty. */
internal fun <T> List<T>.chunkedByBytes(
    budget: Int,
    sizeOf: (T) -> Int,
): List<List<T>> {
    val chunks = mutableListOf<List<T>>()
    var rest = this
    while (rest.isNotEmpty()) {
        val chunk = rest.takeWithinBytes(budget, sizeOf)
        chunks += chunk
        rest = rest.drop(chunk.size)
    }
    return chunks.ifEmpty { listOf(emptyList()) }
}
