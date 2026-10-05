package dev.tandem.core.protocol.fuzz

import com.google.protobuf.InvalidProtocolBufferException
import com.google.protobuf.Parser
import dev.tandem.protocol.v1.CallAction
import dev.tandem.protocol.v1.CallActionResult
import dev.tandem.protocol.v1.CallEvent
import dev.tandem.protocol.v1.CapabilityUnavailable
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.ClipboardText
import dev.tandem.protocol.v1.Commitment
import dev.tandem.protocol.v1.Contact
import dev.tandem.protocol.v1.ContactsSyncRequest
import dev.tandem.protocol.v1.ContactsSyncResponse
import dev.tandem.protocol.v1.CreditGrant
import dev.tandem.protocol.v1.DeviceInfo
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.FileAccept
import dev.tandem.protocol.v1.FileCancel
import dev.tandem.protocol.v1.FileChunk
import dev.tandem.protocol.v1.FileComplete
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.FileReject
import dev.tandem.protocol.v1.FileResumeRequest
import dev.tandem.protocol.v1.FocusState
import dev.tandem.protocol.v1.FocusSyncCapability
import dev.tandem.protocol.v1.GlobalAction
import dev.tandem.protocol.v1.Heartbeat
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.ImeEnter
import dev.tandem.protocol.v1.InputEvent
import dev.tandem.protocol.v1.KeyRotation
import dev.tandem.protocol.v1.KeyframeRequest
import dev.tandem.protocol.v1.ManualPairResult
import dev.tandem.protocol.v1.MediaFormat
import dev.tandem.protocol.v1.MediaFrame
import dev.tandem.protocol.v1.MediaHello
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.MediaTicketGrant
import dev.tandem.protocol.v1.MirrorDeclined
import dev.tandem.protocol.v1.MirrorRequest
import dev.tandem.protocol.v1.Next
import dev.tandem.protocol.v1.NotificationAction
import dev.tandem.protocol.v1.NotificationActionResult
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.NowPlaying
import dev.tandem.protocol.v1.OriginalRequest
import dev.tandem.protocol.v1.PairAccepted
import dev.tandem.protocol.v1.PairChallenge
import dev.tandem.protocol.v1.PairRejected
import dev.tandem.protocol.v1.PairRequest
import dev.tandem.protocol.v1.PhotoError
import dev.tandem.protocol.v1.PhotoMeta
import dev.tandem.protocol.v1.PhotoPage
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.PlaceCallRequest
import dev.tandem.protocol.v1.PlayPause
import dev.tandem.protocol.v1.Previous
import dev.tandem.protocol.v1.RequestMediaTicket
import dev.tandem.protocol.v1.Reveal
import dev.tandem.protocol.v1.Revoke
import dev.tandem.protocol.v1.Ring
import dev.tandem.protocol.v1.RingStop
import dev.tandem.protocol.v1.RotationAck
import dev.tandem.protocol.v1.RotationChallenge
import dev.tandem.protocol.v1.RotationChanged
import dev.tandem.protocol.v1.RotationReject
import dev.tandem.protocol.v1.Scroll
import dev.tandem.protocol.v1.SendSmsRequest
import dev.tandem.protocol.v1.SendSmsStatus
import dev.tandem.protocol.v1.SetText
import dev.tandem.protocol.v1.SimList
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsSyncRequest
import dev.tandem.protocol.v1.SmsSyncResponse
import dev.tandem.protocol.v1.SmsThread
import dev.tandem.protocol.v1.Stop
import dev.tandem.protocol.v1.Swipe
import dev.tandem.protocol.v1.Tap
import dev.tandem.protocol.v1.TextEdit
import dev.tandem.protocol.v1.ThumbRequest
import dev.tandem.protocol.v1.ThumbResult
import dev.tandem.protocol.v1.VersionHello

/**
 * One entry per `.proto` file under `protocol/proto/tandem/v1` (E71-04). Each entry decodes fuzz bytes as
 * every top-level message of that file and is seeded from the listed `protocol/vectors` files.
 * `tools/fuzz/jazzer/check_registry.sh` fails CI naming any proto file without an entry here, so
 * keep the `file = ` literals greppable.
 *
 * The phone only encodes `MediaFrame` fragments (the Mac reassembles them), so `media.proto`
 * fuzzes decoding only; there is no Android reassembly logic to drive.
 */
class DomainFuzzEntry(
    val file: String,
    val vectorFiles: List<String>,
    private val parsers: List<Parser<*>>,
    private val extraDecode: (ByteArray) -> Unit = {},
) {
    fun decode(data: ByteArray) {
        extraDecode(data)
        for (parser in parsers) {
            try {
                parser.parseFrom(data)
            } catch (_: InvalidProtocolBufferException) {
                // malformed input is a legitimate rejection
            }
        }
    }
}

object DomainFuzzRegistry {
    val entries: List<DomainFuzzEntry> =
        listOf(
            DomainFuzzEntry(
                file = "calls.proto",
                vectorFiles = listOf("calls-encoding.json"),
                parsers =
                    listOf(
                        CallEvent.parser(),
                        CallAction.parser(),
                        PlaceCallRequest.parser(),
                        CallActionResult.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "channel.proto",
                vectorFiles = emptyList(),
                parsers = emptyList(),
                extraDecode = { Channel.forNumber(it.firstOrNull()?.toInt() ?: 0) },
            ),
            DomainFuzzEntry(
                file = "clipboard.proto",
                vectorFiles = listOf("clipboard-encoding.json"),
                parsers = listOf(ClipboardText.parser()),
            ),
            DomainFuzzEntry(
                file = "contacts.proto",
                vectorFiles = listOf("contacts-encoding.json"),
                parsers = listOf(Contact.parser(), ContactsSyncRequest.parser(), ContactsSyncResponse.parser()),
            ),
            DomainFuzzEntry(
                file = "control.proto",
                vectorFiles = listOf("heartbeat.json"),
                parsers =
                    listOf(
                        VersionHello.parser(),
                        Heartbeat.parser(),
                        CreditGrant.parser(),
                        MediaTicketGrant.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "envelope.proto",
                vectorFiles = listOf("frame-encoding.json"),
                parsers = listOf(Envelope.parser()),
            ),
            DomainFuzzEntry(
                file = "files.proto",
                vectorFiles = listOf("files-encoding.json"),
                parsers =
                    listOf(
                        FileOffer.parser(),
                        FileAccept.parser(),
                        FileReject.parser(),
                        FileChunk.parser(),
                        FileComplete.parser(),
                        FileCancel.parser(),
                        FileResumeRequest.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "focus.proto",
                vectorFiles = listOf("focus-encoding.json"),
                parsers = listOf(FocusState.parser(), FocusSyncCapability.parser()),
            ),
            DomainFuzzEntry(
                file = "input.proto",
                vectorFiles = listOf("input-encoding.json"),
                parsers =
                    listOf(
                        InputEvent.parser(),
                        Tap.parser(),
                        Swipe.parser(),
                        Scroll.parser(),
                        GlobalAction.parser(),
                        SetText.parser(),
                        ImeEnter.parser(),
                        TextEdit.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "manual_pairing.proto",
                vectorFiles = listOf("manual-pairing.json"),
                parsers = listOf(Commitment.parser(), Reveal.parser(), ManualPairResult.parser()),
            ),
            DomainFuzzEntry(
                file = "media_control.proto",
                vectorFiles = listOf("media-control-encoding.json"),
                parsers =
                    listOf(
                        NowPlaying.parser(),
                        PlayPause.parser(),
                        Next.parser(),
                        Previous.parser(),
                        Stop.parser(),
                        CapabilityUnavailable.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "media.proto",
                vectorFiles = listOf("media-encoding.json", "media-frame-encoding.json"),
                parsers =
                    listOf(
                        RequestMediaTicket.parser(),
                        MediaHello.parser(),
                        MirrorRequest.parser(),
                        MirrorDeclined.parser(),
                        MediaMessage.parser(),
                        MediaFormat.parser(),
                        MediaFrame.parser(),
                        KeyframeRequest.parser(),
                        RotationChanged.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "notify.proto",
                vectorFiles = listOf("notify-encoding.json"),
                parsers =
                    listOf(
                        NotificationPosted.parser(),
                        IconData.parser(),
                        NotificationAction.parser(),
                        NotificationDismiss.parser(),
                        NotificationActionResult.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "pairing.proto",
                vectorFiles = listOf("pairing-proof.json"),
                parsers =
                    listOf(
                        PairChallenge.parser(),
                        DeviceInfo.parser(),
                        PairRequest.parser(),
                        PairAccepted.parser(),
                        PairRejected.parser(),
                        Revoke.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "photos.proto",
                vectorFiles = listOf("photos-encoding.json"),
                parsers =
                    listOf(
                        PhotoPage.parser(),
                        PhotoMeta.parser(),
                        PhotoPageResult.parser(),
                        ThumbRequest.parser(),
                        ThumbResult.parser(),
                        OriginalRequest.parser(),
                        PhotoError.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "rotation.proto",
                vectorFiles = listOf("rotation-encoding.json"),
                parsers =
                    listOf(
                        RotationChallenge.parser(),
                        KeyRotation.parser(),
                        RotationAck.parser(),
                        RotationReject.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "sms.proto",
                vectorFiles = listOf("sms-encoding.json"),
                parsers =
                    listOf(
                        SmsThread.parser(),
                        SmsMessage.parser(),
                        SmsSyncRequest.parser(),
                        SmsSyncResponse.parser(),
                        SendSmsRequest.parser(),
                        SendSmsStatus.parser(),
                        SimList.parser(),
                    ),
            ),
            DomainFuzzEntry(
                file = "status.proto",
                vectorFiles = listOf("status-encoding.json"),
                parsers = listOf(DeviceStatus.parser(), Ring.parser(), RingStop.parser()),
            ),
        )

    /** `name` is the proto file stem, e.g. `media_control`. */
    fun entry(name: String): DomainFuzzEntry? = entries.firstOrNull { it.file == "$name.proto" }
}
