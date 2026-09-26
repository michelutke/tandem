package dev.tandem.feature.pairing.scan

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

private const val TANDEM_QR = "tandem://pair?v=1&fp=fp&s=s&a=192.168.1.10&p=54321&n=n"

class ScanResultFilterTest {
    @Test
    fun scanFilter_tandemQrSeenInTenFrames_parserCalledOnce() {
        val filter = ScanResultFilter()
        val result = ScanResult(format = ScanFormat.QR_CODE, rawValue = TANDEM_QR)

        val outcomes = (1..10).map { filter.apply(result) }

        val accepted = outcomes.filterIsInstance<ScanOutcome.Accept>()
        assertEquals(1, accepted.size)
        assertEquals(TANDEM_QR, accepted.single().rawValue)
        assertEquals(9, outcomes.count { it == ScanOutcome.Ignore })
    }

    @Test
    fun scanFilter_nonQrOrNonTandemValue_ignoredNoParserCall() {
        val filter = ScanResultFilter()

        val nonQrFormat = filter.apply(ScanResult(format = ScanFormat.OTHER, rawValue = TANDEM_QR))
        val nonTandemValue = filter.apply(ScanResult(format = ScanFormat.QR_CODE, rawValue = "https://example.com"))

        assertEquals(ScanOutcome.Ignore, nonQrFormat)
        assertEquals(ScanOutcome.Ignore, nonTandemValue)
    }
}
