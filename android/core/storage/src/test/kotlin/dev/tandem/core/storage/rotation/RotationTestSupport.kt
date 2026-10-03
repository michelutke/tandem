package dev.tandem.core.storage.rotation

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.keyRotation
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

internal class MutableClock(
    var nowMs: Long,
) : Clock() {
    override fun instant(): Instant = Instant.ofEpochMilli(nowMs)

    override fun getZone(): ZoneId = ZoneOffset.UTC

    override fun withZone(zone: ZoneId): Clock = this
}

internal class TestIdentity {
    val keyPair: KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    val spkiDer: ByteArray = keyPair.public.encoded
    val fingerprint: SpkiFingerprint = spkiFingerprint(spkiDer)

    fun sign(message: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(keyPair.private)
            update(message)
            sign()
        }
}

internal fun peerRecord(identity: TestIdentity) =
    PeerRecord(
        deviceId = "mac",
        displayName = "Mac",
        spkiSha256Base64Url = identity.fingerprint.base64Url,
        pairedAtEpochMs = 0L,
        lastSeenEpochMs = 0L,
        capabilities = emptyList(),
    )

internal fun keyRotationEnvelope(
    oldKey: TestIdentity,
    newKey: TestIdentity,
    cb: ByteArray,
    signedOld: TestIdentity = oldKey,
    signedNew: TestIdentity = newKey,
): Envelope {
    val transcript = RotationProof.transcript(oldKey.spkiDer, newKey.spkiDer, cb)
    return envelope {
        channel = Channel.CHANNEL_CONTROL
        keyRotation =
            keyRotation {
                newSpkiDer = ByteString.copyFrom(newKey.spkiDer)
                sigOldKey = ByteString.copyFrom(signedOld.sign(transcript))
                sigNewKey = ByteString.copyFrom(signedNew.sign(transcript))
            }
    }
}
