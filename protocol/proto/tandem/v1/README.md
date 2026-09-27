protocol/proto/tandem/v1 — E01-01: single source of truth .proto messages (envelope, pairing, control, status, notify, clipboard).

## Future proto files (E01-14)

`envelope.proto`'s `Envelope.payload` oneof pre-reserves a field-number range per domain
(docs/protocol/SPEC.md `#framing-and-envelope`) so a later phase can add its `.proto` file without
touching an already-shipped one. Every one of the nine F-3.2 channels (`#channels-and-flow-control-credits`,
frozen by E01-04) already exists in `envelope.proto`'s `Channel` enum; the table below maps each
planned proto file to the channel it will use and the `Envelope.payload` field numbers already
reserved for it.

| Future `.proto` file | Owning epic/issue | Channel | Reserved `Envelope.payload` field numbers |
|---|---|---|---|
| `files.proto` | E40-01 | `CHANNEL_FILES` | 50–59 |
| `photos.proto` | E41-01 | `CHANNEL_FILES` (no `PHOTOS` channel, E01-04 decision) | 60–69 |
| `sms.proto` | E50-01 | `CHANNEL_SMS` | 70–79 |
| `contacts.proto` | E51-01 | `CHANNEL_CONTACTS` | 80–89 |
| `calls.proto` | E52-01 | `CHANNEL_CALLS` | 90–99 |
| `media.proto` | E60-01 / E61-01 | `CHANNEL_CONTROL` (ticket request only; grant is `MediaTicketGrant` in `control.proto`, E01-12, already in the 4–9 range) | none — media frames ride the separate media connection, which carries no `Envelope` and has no channel |
| `input.proto` | E62-01 | `CHANNEL_INPUT` | 100–109 |
| `rotation.proto` | E70-01 | `CHANNEL_CONTROL` | 110–119 |
| `status.proto` extension | E23-01 | `CHANNEL_STATUS` (already `status.proto`'s channel, E01-13) | 22–29 (within status.proto's existing 20–29 range; do not assign before E23-01) |

Rule: adding a domain never adds or renumbers a `Channel` value. The nine channels are frozen; a
new domain gets a new reserved field-number range on an existing channel (or `CONTROL` for
control-plane concerns), never a new enum value — `Channel` renumbering is a `buf breaking` hazard
across every already-paired device.
