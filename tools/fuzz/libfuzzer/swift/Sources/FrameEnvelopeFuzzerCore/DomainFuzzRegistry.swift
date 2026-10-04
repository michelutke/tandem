import Foundation
import MirrorFragmentReassembler
import SwiftProtobuf
import TandemProtocol

/// E71-13: one entry per `protocol/proto/tandem/v1/*.proto` file. Each entry decodes fuzz bytes
/// as every top-level message of that file. `tools/fuzz/libfuzzer/check_registry.sh` fails CI
/// naming any proto file without an entry here, so keep the `file:` literals greppable.
public struct DomainFuzzEntry: Sendable {
    public let file: String
    public let run: @Sendable (Data) -> Void
}

public enum DomainFuzzRegistry {
    public static let entries: [DomainFuzzEntry] = [
        DomainFuzzEntry(file: "calls.proto", run: decodeAll(
            Tandem_V1_CallEvent.self, Tandem_V1_CallAction.self, Tandem_V1_PlaceCallRequest.self,
            Tandem_V1_CallActionResult.self)),
        DomainFuzzEntry(file: "channel.proto", run: { data in
            _ = Tandem_V1_Channel(rawValue: Int(data.first ?? 0))
        }),
        DomainFuzzEntry(file: "clipboard.proto", run: decodeAll(Tandem_V1_ClipboardText.self)),
        DomainFuzzEntry(file: "contacts.proto", run: decodeAll(
            Tandem_V1_Contact.self, Tandem_V1_ContactsSyncRequest.self, Tandem_V1_ContactsSyncResponse.self)),
        DomainFuzzEntry(file: "control.proto", run: decodeAll(
            Tandem_V1_VersionHello.self, Tandem_V1_Heartbeat.self, Tandem_V1_CreditGrant.self,
            Tandem_V1_MediaTicketGrant.self)),
        DomainFuzzEntry(file: "envelope.proto", run: decodeAll(Tandem_V1_Envelope.self)),
        DomainFuzzEntry(file: "files.proto", run: decodeAll(
            Tandem_V1_FileOffer.self, Tandem_V1_FileAccept.self, Tandem_V1_FileReject.self,
            Tandem_V1_FileChunk.self, Tandem_V1_FileComplete.self, Tandem_V1_FileCancel.self,
            Tandem_V1_FileResumeRequest.self)),
        DomainFuzzEntry(file: "focus.proto", run: decodeAll(
            Tandem_V1_FocusState.self, Tandem_V1_FocusSyncCapability.self)),
        DomainFuzzEntry(file: "input.proto", run: decodeAll(
            Tandem_V1_InputEvent.self, Tandem_V1_Tap.self, Tandem_V1_Swipe.self, Tandem_V1_Scroll.self,
            Tandem_V1_GlobalAction.self, Tandem_V1_SetText.self, Tandem_V1_ImeEnter.self,
            Tandem_V1_TextEdit.self)),
        DomainFuzzEntry(file: "manual_pairing.proto", run: decodeAll(
            Tandem_V1_Commitment.self, Tandem_V1_Reveal.self, Tandem_V1_ManualPairResult.self)),
        DomainFuzzEntry(file: "media_control.proto", run: decodeAll(
            Tandem_V1_NowPlaying.self, Tandem_V1_PlayPause.self, Tandem_V1_Next.self,
            Tandem_V1_Previous.self, Tandem_V1_Stop.self, Tandem_V1_CapabilityUnavailable.self)),
        DomainFuzzEntry(file: "media.proto", run: { data in
            decodeAll(
                Tandem_V1_RequestMediaTicket.self, Tandem_V1_MediaHello.self, Tandem_V1_MirrorRequest.self,
                Tandem_V1_MirrorDeclined.self, Tandem_V1_MediaMessage.self, Tandem_V1_MediaFormat.self,
                Tandem_V1_MediaFrame.self, Tandem_V1_KeyframeRequest.self,
                Tandem_V1_RotationChanged.self)(data)
            fuzzFragmentSequence(data)
        }),
        DomainFuzzEntry(file: "notify.proto", run: decodeAll(
            Tandem_V1_NotificationPosted.self, Tandem_V1_IconData.self, Tandem_V1_NotificationAction.self,
            Tandem_V1_NotificationDismiss.self, Tandem_V1_NotificationActionResult.self)),
        DomainFuzzEntry(file: "pairing.proto", run: decodeAll(
            Tandem_V1_PairChallenge.self, Tandem_V1_DeviceInfo.self, Tandem_V1_PairRequest.self,
            Tandem_V1_PairAccepted.self, Tandem_V1_PairRejected.self, Tandem_V1_Revoke.self)),
        DomainFuzzEntry(file: "photos.proto", run: decodeAll(
            Tandem_V1_PhotoPage.self, Tandem_V1_PhotoMeta.self, Tandem_V1_PhotoPageResult.self,
            Tandem_V1_ThumbRequest.self, Tandem_V1_ThumbResult.self, Tandem_V1_OriginalRequest.self,
            Tandem_V1_PhotoError.self)),
        DomainFuzzEntry(file: "rotation.proto", run: decodeAll(
            Tandem_V1_RotationChallenge.self, Tandem_V1_KeyRotation.self, Tandem_V1_RotationAck.self,
            Tandem_V1_RotationReject.self)),
        DomainFuzzEntry(file: "sms.proto", run: decodeAll(
            Tandem_V1_SmsThread.self, Tandem_V1_SmsMessage.self, Tandem_V1_SmsSyncRequest.self,
            Tandem_V1_SmsSyncResponse.self, Tandem_V1_SendSmsRequest.self, Tandem_V1_SendSmsStatus.self,
            Tandem_V1_SimList.self)),
        DomainFuzzEntry(file: "status.proto", run: decodeAll(
            Tandem_V1_DeviceStatus.self, Tandem_V1_Ring.self, Tandem_V1_RingStop.self))
    ]

    /// `name` is the proto file stem, e.g. `media_control`.
    public static func entry(named name: String) -> DomainFuzzEntry? {
        entries.first { $0.file == "\(name).proto" }
    }

    private static func decodeAll(_ types: any Message.Type...) -> @Sendable (Data) -> Void {
        let decoders = types
        return { data in
            for type in decoders {
                _ = try? type.init(serializedBytes: data)
            }
        }
    }
}

/// E71-13: drives `FragmentReassembler` (E61-14) with the fuzz bytes read as 4-byte headers
/// `pts, fragmentIndex, fragmentCount, length` each followed by `length` payload bytes. Reassembly
/// rejections are expected; only a trap or memory-safety finding is a failure.
public func fuzzFragmentSequence(_ data: Data) {
    var reassembler = FragmentReassembler()
    var offset = data.startIndex
    while data.endIndex - offset >= 4 {
        let pts = UInt64(data[offset])
        let index = UInt32(data[offset + 1])
        let count = UInt32(data[offset + 2])
        let length = Int(data[offset + 3])
        offset += 4
        let end = min(offset + length, data.endIndex)
        _ = try? reassembler.accept(pts: pts, fragmentIndex: index, fragmentCount: count, data: data[offset..<end])
        offset = end
    }
}
