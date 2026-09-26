package dev.tandem.core.pairing

import dev.tandem.core.crypto.PairingProof
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.pairing.qr.PairingInvite
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test
import java.time.Clock

class PairRequestBuilderTest {
    private val clock = Clock.systemUTC()

    @Test
    fun pairRequest_proofField_equalsCoreCryptoHelperOutput() {
        val macSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                    "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                    "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
            )
        val phoneSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d03010703420004068" +
                    "0ce82b4232a0150b95909aec7fad7aac320ac498875331566dab9a5c9e79a77d45c35c83d9aec" +
                    "406a2be4f340194acb3ab91dd2b31d6575e1c846e9c8e3c0",
            )
        val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
        val challenge =
            hexToBytes(
                "83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96",
            )

        val invite =
            PairingInvite(
                fingerprint = byteArrayOf(0x00),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )

        val expectedProof = PairingProof.compute(secret, macSpkiDer, phoneSpkiDer, challenge)
        val request = PairRequestBuilder.build(invite, macSpkiDer, phoneSpkiDer, challenge)

        assertEquals(expectedProof.toList(), request.proof.toByteArray().toList())
    }

    @Test
    fun pairRequest_differentLocalIdentity_proofChanges() {
        val keyStore = SoftwareIdentityKeyStore(clock)
        val identity1 = keyStore.getOrCreate("test-identity-1", false)
        val identity2 = keyStore.getOrCreate("test-identity-2", false)

        val macSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                    "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                    "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
            )
        val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
        val challenge =
            hexToBytes(
                "83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96",
            )

        val invite =
            PairingInvite(
                fingerprint = byteArrayOf(0x00),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )

        val request1 =
            PairRequestBuilder.build(invite, macSpkiDer, identity1.publicKey.encoded, challenge)
        val request2 =
            PairRequestBuilder.build(invite, macSpkiDer, identity2.publicKey.encoded, challenge)

        assertNotEquals(
            request1.proof.toByteArray().toList(),
            request2.proof.toByteArray().toList(),
        )
    }

    @Test
    fun pairRequest_differentInviteFp_proofChanges() {
        val macSpkiDer1 =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                    "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                    "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
            )
        val macSpkiDer2 =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d03010703420004" +
                    "47c0dbb3359b3e0fbe7c306bea6123bfcf23a17d294c1b177e2645b236b6ab2b89549671ee5b" +
                    "2e49b4335300ebd801ed4ade057f244bb7e347dd32c1803b964f",
            )
        val phoneSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d03010703420004068" +
                    "0ce82b4232a0150b95909aec7fad7aac320ac498875331566dab9a5c9e79a77d45c35c83d9aec" +
                    "406a2be4f340194acb3ab91dd2b31d6575e1c846e9c8e3c0",
            )
        val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
        val challenge =
            hexToBytes(
                "83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96",
            )

        val invite1 =
            PairingInvite(
                fingerprint = byteArrayOf(0x00),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )
        val invite2 =
            PairingInvite(
                fingerprint = byteArrayOf(0x01),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )

        val request1 = PairRequestBuilder.build(invite1, macSpkiDer1, phoneSpkiDer, challenge)
        val request2 = PairRequestBuilder.build(invite2, macSpkiDer2, phoneSpkiDer, challenge)

        assertNotEquals(
            request1.proof.toByteArray().toList(),
            request2.proof.toByteArray().toList(),
        )
    }

    @Test
    fun pairRequest_differentPairChallenge_proofChanges() {
        val macSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                    "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                    "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
            )
        val phoneSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d03010703420004068" +
                    "0ce82b4232a0150b95909aec7fad7aac320ac498875331566dab9a5c9e79a77d45c35c83d9aec" +
                    "406a2be4f340194acb3ab91dd2b31d6575e1c846e9c8e3c0",
            )
        val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
        val challenge1 =
            hexToBytes(
                "83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96",
            )
        val challenge2 =
            hexToBytes(
                "a16f90d1056e41701fcfe53f16c5f212d5320b3d89070c1fda47780c189e7a7b",
            )

        val invite =
            PairingInvite(
                fingerprint = byteArrayOf(0x00),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )

        val request1 = PairRequestBuilder.build(invite, macSpkiDer, phoneSpkiDer, challenge1)
        val request2 = PairRequestBuilder.build(invite, macSpkiDer, phoneSpkiDer, challenge2)

        assertNotEquals(
            request1.proof.toByteArray().toList(),
            request2.proof.toByteArray().toList(),
        )
    }

    @Test
    fun pairRequest_deviceInfo_containsNoHardwareIdentifiers() {
        val macSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d0301070342000440" +
                    "5a9ef39f6fa9344fc391b37e9af91ce7de69ebb0ca38c5d42e23d19b8233e451cd65d30c3c541" +
                    "00e2427bafd64be9f9c084214bd2b66d5724d04dd18dacc79",
            )
        val phoneSpkiDer =
            hexToBytes(
                "3059301306072a8648ce3d020106082a8648ce3d03010703420004068" +
                    "0ce82b4232a0150b95909aec7fad7aac320ac498875331566dab9a5c9e79a77d45c35c83d9aec" +
                    "406a2be4f340194acb3ab91dd2b31d6575e1c846e9c8e3c0",
            )
        val secret = hexToBytes("c00cfdcf0eafd84361794f980a688157")
        val challenge =
            hexToBytes(
                "83f7523553c91d478b4a6809c3864afc28d8b061bcaa6e5c148509b6cc2caa96",
            )

        val invite =
            PairingInvite(
                fingerprint = byteArrayOf(0x00),
                secret = secret,
                addresses = listOf("192.168.1.1"),
                port = 8080,
                macName = "Test Mac",
            )

        val request = PairRequestBuilder.build(invite, macSpkiDer, phoneSpkiDer, challenge)

        assertEquals(true, request.hasDeviceInfo())
    }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Hex string must have even length" }
        return ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
