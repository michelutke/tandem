protocol/proto/tandem/v1 — E01-01: single source of truth .proto messages (envelope, pairing, control, status, notify, clipboard, files, photos, contacts, sms, calls, media, rotation, focus, media_control).

## Future proto files (E01-14)

`envelope.proto`'s `Envelope.payload` oneof pre-reserves a field-number range per domain
(docs/protocol/SPEC.md `#framing-and-envelope`) so a later phase can add its `.proto` file without
touching an already-shipped one. Every one of the nine F-3.2 channels (`#channels-and-flow-control-credits`,
frozen by E01-04) already exists in `envelope.proto`'s `Channel` enum; the table below maps each
planned proto file to the channel it will use and the `Envelope.payload` field numbers already
reserved for it.

| Future `.proto` file | Owning epic/issue | Channel | Reserved `Envelope.payload` field numbers |
|---|---|---|---|
| `contacts.proto` | E51-01 | `CHANNEL_CONTACTS` | 80–89 |
| `media.proto` | E60-01 / E61-01 | `CHANNEL_CONTROL` (`RequestMediaTicket` = 8, written by E60-01; grant is `MediaTicketGrant` in `control.proto`, E01-12) | 8 (`RequestMediaTicket`) — `MediaHello` and E61-01 `MediaMessage` (`MediaFormat`, `MediaFrame`, `KeyframeRequest`, `RotationChanged`) ride the separate media connection, which carries no `Envelope` and has no channel |
| `input.proto` | E62-01 | `CHANNEL_INPUT` | 100–109 |
| `rotation.proto` | E70-01 | `CHANNEL_CONTROL` | 110–113 (`RotationChallenge`, `KeyRotation`, `RotationAck`, `RotationReject`, written by E70-01); 114–119 held |
| `focus.proto` | E72-04 | `CHANNEL_CONTROL` | 120–121 (`FocusState`, `FocusSyncCapability`, written by E72-04); 122–129 held |
| `media_control.proto` | E72-02 | `CHANNEL_STATUS` (device-state domain, like `Ring`/`RingStop`; SPEC.md §4 closed channel set) | 130–135 (`NowPlaying`, `PlayPause`, `Next`, `Previous`, `Stop`, `CapabilityUnavailable`, written by E72-02); 136–139 held |
| `status.proto` extension | E23-01 | `CHANNEL_STATUS` (already `status.proto`'s channel, E01-13) | 22–29 (within status.proto's existing 20–29 range; do not assign before E23-01) |

Rule: adding a domain never adds or renumbers a `Channel` value. The nine channels are frozen; a
new domain gets a new reserved field-number range on an existing channel (or `CONTROL` for
control-plane concerns), never a new enum value — `Channel` renumbering is a `buf breaking` hazard
across every already-paired device.
