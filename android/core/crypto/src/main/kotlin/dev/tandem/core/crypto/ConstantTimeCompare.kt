package dev.tandem.core.crypto

/**
 * Constant-time equality check for secrets (invariant 6): no data-dependent branching or early
 * exit once the lengths are known to match. Used by the fingerprint pin comparison (E12-05) and
 * any future secret comparison in core/crypto.
 */
fun constantTimeEquals(
    a: ByteArray,
    b: ByteArray,
): Boolean = constantTimeEquals(a, b, ByteAccessCounter())

/**
 * Test seam (E10-10): counts every byte read so tests can assert the compare always scans the
 * full length, regardless of where the first mismatch is. Not exported from core/crypto.
 */
internal class ByteAccessCounter {
    var accessCount: Int = 0
        private set

    fun record() {
        accessCount++
    }
}

internal fun constantTimeEquals(
    a: ByteArray,
    b: ByteArray,
    counter: ByteAccessCounter,
): Boolean {
    if (a.size != b.size) return false

    var diff = 0
    for (i in a.indices) {
        counter.record()
        val byteA = a[i]
        counter.record()
        val byteB = b[i]
        diff = diff or (byteA.toInt() xor byteB.toInt())
    }
    return diff == 0
}
