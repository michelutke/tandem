# Tandem Wire Protocol Specification

**Status:** Draft v1 — sections are added incrementally as their owning backlog issue (see
`docs/planning/backlog/*.yaml`) is completed. The [section map](#section-map) below lists every
planned section; a section marked `TBD` has not been written yet and MUST NOT be treated as
normative until it is.

Where this document conflicts with `docs/PRD.md`, this document and
`docs/planning/decisions.md` win (`docs/planning/decisions.md` D-40; `CLAUDE.md`). Every
normative statement here is traceable to a PRD functional requirement (`F-x.y`), a decision row
(`D-nn`), or an acceptance criterion (`AC-nn`) in the backlog; those references are given inline.

## Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119). Every one of these key words in this document
is normative; prose that does not use one of them is explanatory, not a requirement.

All multi-byte integers on the wire are big-endian unless a section states otherwise. Byte counts
are given in decimal; "1 MiB" always means exactly 1 048 576 bytes (2^20).

### Section anchors

Every `##`-level section heading below has a stable Markdown anchor derived by the standard GitHub
slug rule: lowercase the heading text, drop characters other than letters, digits, spaces and
hyphens, then replace runs of whitespace with a single hyphen. For example "Framing and envelope"
resolves to `#framing-and-envelope`. Anchors are part of this document's contract: once a section
is written, its heading text (and therefore its anchor) MUST NOT change without updating every
`.proto` comment and backlog row that cites it. Anchors for `TBD` sections are reserved now so
that `.proto` files and other SPEC sections can cite them ahead of time.

## Section map

| # | Section | Anchor | Status |
|---|---|---|---|
| 1 | Handshake and TLS profile | [`#handshake-and-tls-profile`](#handshake-and-tls-profile) | Written (E01-01) |
| 2 | Pairing | [`#pairing`](#pairing) | Written (E01-02) |
| 3 | Framing and envelope | [`#framing-and-envelope`](#framing-and-envelope) | Written (this issue, E01-03) |
| 4 | Channels and flow-control credits | [`#channels-and-flow-control-credits`](#channels-and-flow-control-credits) | Written (E01-04) |
| 5 | Errors and close codes | [`#errors-and-close-codes`](#errors-and-close-codes) | Written (this issue, E01-05) |
| 6 | Versioning and capability negotiation | [`#versioning-and-capability-negotiation`](#versioning-and-capability-negotiation) | Written (E01-06) |
| 7 | Heartbeat | [`#heartbeat`](#heartbeat) | Written (E01-07) |
| 8 | Discovery TXT record | [`#discovery-txt-record`](#discovery-txt-record) | Written (E01-08) |
| 9 | Media ticket | [`#media-ticket`](#media-ticket) | Written (E01-09, E60-01) |
| 10 | Timeouts, connection limits and resource caps | [`#timeouts-connection-limits-and-resource-caps`](#timeouts-connection-limits-and-resource-caps) | Written (E01-22) |
| 11 | Untrusted peer strings (display sanitization) | [`#untrusted-peer-strings-display-sanitization`](#untrusted-peer-strings-display-sanitization) | Written (E01-23) |
| 12 | Media frame semantics | `#media-frame-semantics` | TBD in E61-01 (extends §9, Phase 6) |
| 13 | Input events | `#input-events` | TBD (Phase 6, epic E62) |
| 14 | SMS channel | [`#sms-channel`](#sms-channel) | Written (E50-01) |
| 15 | Contacts channel | [`#contacts-channel`](#contacts-channel) | Written (E51-01) |
| 16 | Calls channel | [`#calls-channel`](#calls-channel) | Written (E52-01) |
| 17 | Key rotation | [`#key-rotation`](#key-rotation) | Written (E70-01) |
| 18 | STATUS channel | [`#status-channel`](#status-channel) | Written (E23-01) |
| 19 | NOTIFY channel | [`#notify-channel`](#notify-channel) | Written (E30-01) |
| 20 | CLIPBOARD channel | [`#clipboard-channel`](#clipboard-channel) | Written (E31-01) |
| 21 | FILES channel | [`#files-channel`](#files-channel) | Written (E40-01) |
| 22 | Focus sync | [`#focus-sync`](#focus-sync) | Written (E72-04) |

Sections 1–11 are the Phase 0 `SPEC.md` v1 set (`docs/planning/traceability.md`, "`SPEC.md` v1"
row). Sections 12–17 are reserved slots for later phases so that earlier sections' numbering and
anchors never change; new sections are always appended after the last row in this table, never
inserted between existing rows.

---

## Handshake and TLS profile

*(E01-01 · PRD F-3.1 · AC-01, AC-04, AC-13, AC-15 · invariants 1, 2, 5, 6)*

This section defines the TLS profile every connection (control and media, §9) MUST negotiate, the
verify-callback algorithm each side runs to turn a bare TLS handshake into a trust decision bound to
a pinned SPKI (invariant 3), and the channel-binding value `cb` that later sections (§2 pairing,
E70-01 key rotation) bind higher-layer proofs to one specific TLS session. Deadlines and connection
counts that bound the handshake (TLS 10 s, `VersionHello` 5 s, pre-authentication connection caps)
are defined once, in §10 (`#timeouts-connection-limits-and-resource-caps`, E01-22), not here.

### TLS version and cipher profile

- Both sides MUST negotiate TLS 1.3 only and MUST reject a TLS 1.2-or-lower `ClientHello` or
  `ServerHello`.
- The negotiated cipher suite MUST be one of the TLS 1.3 AEAD suites: `TLS_AES_128_GCM_SHA256`,
  `TLS_AES_256_GCM_SHA384`, or `TLS_CHACHA20_POLY1305_SHA256`. This protocol does not restrict which
  key-exchange group is offered or selected; implementations MAY offer any group their platform TLS
  stack supports (X25519, secp256r1, and hybrid post-quantum groups where available).
- The certificate signature scheme MUST be `ecdsa_secp256r1_sha256` only.
- ALPN: the client MUST offer exactly the protocol identifier `tandem/1` and no other value; the
  server MUST select it. A `ClientHello` offering a missing or different ALPN value, or a `ServerHello`
  selecting anything other than `tandem/1`, MUST fail the handshake.
- No SNI is sent by the client: the phone always dials a literal IP address (from the trust store, or
  from the QR `a` field during pairing, §2), never a hostname, so there is no hostname to place in SNI.
- No session resumption: the server MUST NOT issue a usable session ticket, and both sides MUST NOT
  resume a session (new or abbreviated) on a subsequent connection. The Android client MUST use a
  fresh `SSLContext` per connection and MUST disable session tickets on it
  (`SSLSockets.setUseSessionTickets(socket, false)`), so it never even offers a PSK identity.
- No 0-RTT: both sides MUST NOT send or accept 0-RTT (early) application data.
- No post-handshake authentication: neither side re-authenticates a peer after the initial handshake
  completes; a peer's identity for the lifetime of a connection is exactly the leaf certificate seen
  during that one handshake.
- The Mac (the sole TLS listener, ADR-002) MUST require a client certificate on every connection to
  its listener; a `ClientHello`/handshake that completes with no client certificate presented MUST
  fail — there is no server-only-authenticated mode anywhere in this protocol.

### Certificate handling and the leaf-only check

- Both sides use self-signed identity certificates (there is no CA in this protocol). Only the peer's
  leaf certificate is ever examined; any additional certificates a peer sends MUST be ignored and MUST
  NOT be used for trust in any way.
- Certificate validity dates, subject, SAN, extended key usage, and key usage extensions are NOT
  checked — trust is the SPKI pin (below), never any X.509 field designed for CA-issued certificates.
- The leaf's public key MUST be an uncompressed P-256 `SubjectPublicKeyInfo`, exactly 91 bytes of DER
  encoding. A leaf key of any other type, curve, or point encoding (including a compressed P-256
  point) MUST fail the handshake before the pin compare (below) ever runs: no fingerprint computed
  from a non-conforming key could ever equal a pinned value, so this check is a precondition of the
  verify callback, not a separate failure path — its failure is reported through the same TLS
  handshake-failure signal as an ordinary pin mismatch (§5, `#errors-and-close-codes`, `PIN_MISMATCH`).

### Verify-callback algorithm

Each side's verify callback (`sec_protocol_options_set_verify_block` on macOS, `X509TrustManager` on
Android — `X509ExtendedKeyManager` is the Android client-certificate *selector*, a distinct role from
the trust-verification callback this algorithm describes) runs the following steps, in order, for the
peer certificate seen on this handshake:

1. Extract the peer's leaf certificate.
2. Check the leaf's public key is an uncompressed P-256 SPKI, exactly 91 bytes of DER (§ Certificate
   handling, above); if not, fail the handshake now, before step 3.
3. Compute SHA-256 over the leaf's DER-encoded `SubjectPublicKeyInfo` — the candidate fingerprint.
4. Compare the candidate fingerprint, in constant time (invariant 6), against every fingerprint this
   side's trust store holds.
5. On a match: accept. The connection proceeds as an ordinary session for the peer identity the
   matched trust-store entry names.
6. On no match:
   - **The Mac only** MAY still accept the connection, but only while a pairing window (§2,
     `#pairing`) is open and only for the pairing exchange on that one connection (D-18: at most one
     such pairing-candidate connection at a time; a second unknown client certificate while one is
     already in flight MUST be rejected here, without evaluating anything else, and MUST NOT burn a
     pairing attempt — §10, `#timeouts-connection-limits-and-resource-caps`).
   - Otherwise (no pairing window open, the pairing-candidate slot already occupied, or this is the
     phone verifying the Mac's certificate — the phone has no equivalent relaxation, invariant 4), the
     handshake MUST fail inside the callback, before any application data is exchanged.
- **The phone** MUST pin the Mac's SPKI — from its trust store for an already-paired Mac, or from the
  QR `fp` field (§2) while a pairing scan is in progress — and MUST NOT accept any other server key,
  even during its own in-progress pairing scan. There is no "unknown server key" relaxation anywhere
  on the phone side; only the Mac, as the listening side, ever accepts an unpinned peer, and only
  under the pairing-window carve-out above.
- Every fingerprint comparison in this algorithm MUST be constant time (invariant 6).
- The pin check above is in addition to, never instead of, the TLS stack's own `CertificateVerify`
  validation: a peer presenting a pinned certificate without possessing the matching private key MUST
  still fail the handshake, since `CertificateVerify` is enforced by the native TLS stack independently
  of this callback (confirmed on both platforms, E03-01, E03-03).
- Every failure in this algorithm MUST close the connection with no plaintext or reduced-security
  retry of any kind (invariant 2), and MUST be surfaced as a close code from §5
  (`#errors-and-close-codes`) with a visible error wherever §5's UI rules require one (invariant 5).

### Channel binding (`cb`)

Per `docs/planning/decisions.md` D-67, channel binding in this protocol is derived by an **in-band
challenge on every platform and API level** — there is no RFC 9266 TLS-exporter code path anywhere in
this version of the protocol.

- Two typed CONTROL messages carry a channel-binding challenge: `PairChallenge { challenge }`
  (`pairing.proto`, E01-11, consumed by §2 below) and `RotationChallenge { challenge }`
  (`rotation.proto`, E70-01, Phase 7 — named here only; key rotation itself is defined in a later
  SPEC section). Both carry exactly one field, `challenge`, exactly 32 bytes generated by a CSPRNG for
  every issuance.
- **Mechanism.** For that session, `cb = challenge`: the 32 bytes themselves, unmodified — no
  signature, hash, or further derivation is applied to produce `cb`. A consumer that additionally
  needs to prove key possession signs material that includes `cb` as one of its inputs (e.g. the
  Phase 7 `KeyRotation` signature); the challenge itself is never re-signed to derive `cb`. The two
  consumers trigger issuance differently:
  - **Pairing (§2).** Once a pairing-candidate connection's `VersionHello` exchange (§6) completes,
    the Mac — the verifying side — MUST generate a fresh 32-byte CSPRNG challenge and send it as
    `PairChallenge` before sending or accepting any other payload on that connection (§2, Frame
    order). This is the only trigger for `PairChallenge`; it is never sent again on that connection.
  - **Key rotation (E70-01, Phase 7; `docs/planning/decisions.md` D-74).** Each side MUST send
    exactly one unsolicited `RotationChallenge` on every control session immediately once that
    session reaches Ready (hello exchange complete on a connection whose peer matched the trust
    store; a pairing candidate reaches Ready only when `PairAccepted` is sent/received) — not only
    when a rotation is imminent, and regardless of whether either side ever actually rotates on that
    session. The value is valid only on that one session and only for exactly one `KeyRotation`; a
    re-sent `KeyRotation` for the already-pinned `newSpki` (E70-01 idempotent rule) is the same use
    and is acknowledged without re-verifying against the challenge. A session's own
    `RotationChallenge` is never resent on that same session. A `RotationChallenge` is never legal on
    a pairing-candidate connection before `PairAccepted`: any payload other than the pairing sequence
    or `Heartbeat` there is a wrong payload under §2's frame-order rule (local reason `MALFORMED`:
    `PairRejected(PAIRING_UNAVAILABLE)`, close `PAIRING_FAILED`, one attempt burned).
- **What `cb` binds, and what it does not.** The 32 bytes are fresh per session and never reused, and
  reachable at all only once this session's verify-callback pin check has already passed (above), so
  the challenge exchange adds no new trust decision. This gives `cb` **replay** protection: a proof or
  signature computed against one session's `cb` is never valid replayed onto a different session
  between the same two keys, because the challenge simply never repeats. `cb` does **not**, by itself,
  detect a **relay**: an attacker who terminates TLS separately with each honest party is a party to
  both resulting sessions and can simply forward the challenge value it receives on one session as the
  challenge it sends on the other, so `cb` can be identical on both sides of a relay. Relay/evil-QR
  detection instead comes from `LP(macSpkiDer) || LP(phoneSpkiDer)` in the proof transcript (§2,
  Proof computation) together with TLS `CertificateVerify` (§ Verify-callback algorithm, above): an
  attacker relaying between two honest parties must use its own key on at least one side of the relay —
  it holds neither the real Mac's nor the real phone's private key — so the two sessions' SPKI pairs,
  and therefore both the proof and the confirmation code that are keyed on them, differ even when the
  relayed `cb` is identical. §2's confirmation code relies on this SPKI-pair difference, not on `cb`,
  for evil-QR detection (`docs/planning/decisions.md` D-71; see §2, Confirmation code). This corrects an
  earlier draft of this section, which claimed the relay case produces two distinct `cb` values — it
  does not under this in-band-challenge design, since the attacker chooses what to forward; the
  `docs/spikes/channel-binding.md` "Relay/MITM given pinning" analysis this earlier draft leaned on
  assumes both sides are already honestly pinned to each other, which is a narrower premise than the
  evil-QR scenario here, where the phone has not yet pinned anything and is deciding whether to trust
  the QR it scanned.
- `cb` MUST NOT be logged or persisted; a session that needs a channel-binding value always receives a
  freshly generated challenge, never a cached or reused one.
- The consumers of `cb` defined so far are the pairing proof and confirmation code (§2, `#pairing`,
  E01-02) and the Phase 7 `KeyRotation` signature (E70-01); both are defined against this general `cb`
  primitive, not against session-specific detail — this section is the single normative definition of
  `cb`. No transport session exposes or derives `cb`: `TandemSession` (E12-11, E12-12) carries frames
  only and has no channel-binding or exporter property of any kind; each consumer above generates,
  sends, and holds its own challenge value entirely within its own layer (E14 for pairing, E70 for
  rotation).
- **History note.** Backlog text from review cycles 4–5 (`docs/planning/backlog/phase-0.yaml`,
  `phase-1.yaml`, `phase-7.yaml`) originally described the RFC 9266 TLS exporter as the primary
  channel-binding mechanism, with this in-band challenge only as a fallback for a platform that could
  not export keying material (the original D-15 decision). `docs/planning/decisions.md` D-67
  superseded this following the E03-04 end-to-end spike, and the backlog text was updated to match in
  review cycle 8: the in-band challenge above applies unconditionally, on every platform and API
  level; there is no exporter code path and no `Build.VERSION.SDK_INT` branch anywhere in this
  design.

### Platform implementation notes

These are normative MUSTs for the two platform implementations, recorded here because each was found
by a Phase 0 spike to be necessary for the TLS profile above to actually work, not merely an
implementation preference (`docs/adr/ADR-003-mtls-vs-noise.md`, Consequences):

- **Android.** The `IdentityKeyStore` (E10-15) MUST generate its P-256 identity key with
  `setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)`. Omitting `DIGEST_NONE`
  produces a key that generates and presents a certificate normally but fails every handshake with an
  opaque I/O error: Conscrypt signs the TLS 1.3 `CertificateVerify` over the already-computed
  transcript hash directly, using a `NONEwithECDSA` JCA `Signature` engine (the digest is pre-computed
  by the TLS stack itself, not by the `Signature` engine), and `NONEwithECDSA` against a key whose
  `setDigests()` list does not include `DIGEST_NONE` fails inside `AndroidKeyStore`
  (`docs/spikes/android-sslsocket-keystore.md`, E03-03 critical finding).
- **macOS.** The Mac listener (`core/transport`, E12-04) MUST add an explicit application-level ALPN
  check in its ready handler — `negotiatedALPN == "tandem/1"`, else cancel the connection — because
  `Network.framework` enforces a *mismatched* ALPN offer but silently accepts a client that offers *no*
  ALPN extension at all (`docs/spikes/nwlistener-mtls.md` §5, E03-01). Relying on `Network.framework`'s
  own enforcement alone would let a client that omits the ALPN extension complete a handshake this
  section's ALPN requirement (above) requires rejecting.

### Failure behavior

Every handshake failure defined in this section MUST close the connection with no plaintext or
reduced-security retry of any kind (invariant 2), and MUST surface a visible error mapped to a close
code from §5 (`#errors-and-close-codes`). The same underlying event — an unrecognized client
certificate — maps to three different close codes depending on which of three distinct circumstances
applies, and implementations MUST NOT conflate them:

- `PIN_MISMATCH` for an unknown key rejected in the verify callback with no pairing window open
  (§ Verify-callback algorithm, step 6) — or `REVOKED`, per §5 row 7, if this side had previously
  pinned the peer;
- `LIMIT_EXCEEDED` when an unknown key is rejected specifically because the single pairing-candidate
  slot is already occupied by another in-flight candidate (§10,
  `#timeouts-connection-limits-and-resource-caps`; §2's Concurrency rule) — a distinct rejection reason
  from an ordinary pin mismatch even though both are decided inside the same verify callback; and
- on the phone only, a TLS handshake-failure alert received while dialing a pairing-candidate
  connection maps to `PAIRING_FAILED`, not `PIN_MISMATCH` (§5, `docs/planning/decisions.md` D-58) —
  scoped to a pairing dial specifically because the phone's own pin check against the QR `fp` has
  already passed by the time such an alert could arrive, so the Mac's identity is not in question.

`VERSION_MISMATCH` is a separate case, for the post-handshake `VersionHello` comparison (§6, which
necessarily runs after this section's handshake has already succeeded). Deadlines and connection-count
caps governing this handshake — the TLS 10 s deadline, the `VersionHello` 5 s deadline, and the
pre-authentication connection caps — are defined once, in §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22).

---

## Pairing

*(E01-02 · PRD F-2.1 · UC-03, AC-03, AC-14, AC-17, AC-20 · invariants 3, 5, 6)*

This section defines how a phone and a Mac that have never met establish their first mutual trust:
the QR code the Mac displays, the pairing-candidate mTLS connection §1's verify callback admits while
a pairing window is open, the proof and confirmation-code formulas bound to that connection's channel
binding (§1), and the mutual-confirmation flow that defends against a substituted ("evil") QR code.

### QR payload grammar

The Mac renders one QR code per open pairing window, encoding a `tandem://pair` URI:

```
pair-uri     = "tandem://pair?v=1&fp=" fp "&s=" s "&a=" addr-list "&p=" port "&n=" name
fp           = 1*BASE64URL          ; base64url, no padding; decodes to exactly 32 bytes
s            = 1*BASE64URL          ; base64url, no padding; decodes to exactly 16 bytes
addr-list    = literal-addr *7("," literal-addr)   ; 1 to 8 literal addresses, no hostnames
literal-addr = IPv4address / IPv6address   ; RFC 3986 §3.2.2 productions, no zone ID
port         = 1*5DIGIT             ; decimal, 1..65535, no leading zeros
name         = *(unreserved / pct-encoded)  ; RFC 3986 §2.3 unreserved, or percent-encoded UTF-8;
                                     ; decodes to at most 64 bytes
BASE64URL    = ALPHA / DIGIT / "-" / "_"
```

`literal-addr` is exactly RFC 3986's `IPv4address` or `IPv6address` production (§3.2.2); no zone
identifier (e.g. a trailing `%25en0`) is permitted on an IPv6 literal, and one present anywhere in `a`
MUST be rejected. `port`'s `1*5DIGIT` MUST NOT carry a leading zero (`00080` MUST be rejected) except
for the single digit `0` itself, which is separately out of the 1..65535 range and therefore already
rejected on that basis. A loopback address (`127.0.0.1`, `::1`) is not one of the forbidden categories
below (unspecified, multicast, broadcast) and so is not itself rejected by this grammar; the Mac's own
QR-rendering implementation (E14-01) simply never emits one, since a loopback address is never a
useful address for the phone to dial.

Fields, in this order, and every field's parse/reject rule:

- `v` MUST equal the literal `1`; any other value MUST be rejected (unlike the discovery TXT record's
  `v`, §8, which is silently ignored — this is the pairing URI itself being scanned, not a background
  advertisement, so an unrecognized version is a hard parse failure, not something to skip past).
- `fp` — base64url (no padding) encoding of the Mac's 32-byte SPKI SHA-256 fingerprint, the same value
  §1's verify callback computes and compares.
- `s` — base64url (no padding) encoding of the 16-byte, CSPRNG-generated, single-use pairing secret.
- `a` — a comma-separated list of 1 to 8 literal IPv4 or IPv6 addresses. A hostname anywhere in the
  list, more than 8 addresses, or an address that is unspecified (`0.0.0.0`, `::`), multicast, or the
  broadcast address (`255.255.255.255`) MUST be rejected.
- `p` — a decimal TCP port, 1–65535: the Mac's single listener (`docs/planning/decisions.md` D-03).
- `n` — a percent-encoded, UTF-8 device/owner-supplied display name for the Mac, at most 64 bytes after
  percent-decoding; sanitized before display per §11
  (`#untrusted-peer-strings-display-sanitization`, E01-23) and never trusted for any decision.

A parser MUST reject a payload with any field missing, duplicated, mis-encoded, or out of the
range/grammar stated above, and MUST reject any `v` other than `1`. These restrictions on `a` and `n`
exist specifically so a malformed or substituted QR payload cannot smuggle a DNS lookup, an oversized
allocation, or a display-spoofing string into the pairing flow (`docs/threat-model.md` §4.3).

### Pairing window

- The window MUST expire 120 s after opening; the secret and the window expire together.
- At most 3 attempts are permitted; the Mac MUST reject a 4th attempt without evaluating its proof.
  Attempt exhaustion closes the window entirely, exactly like a success or an expiry: a 4th candidate
  connection is rejected in the verify callback (§1) — because the window is already closed, there is
  no in-flight pairing-candidate slot for it to occupy — and it never reaches proof evaluation.
- The secret is single-use: a successful pairing MUST close the window and destroy the secret; the
  same secret MUST NOT be reused for a second phone, even within the 120 s / 3-attempt budget.
- **Secret handling.** The secret is 16 bytes from a CSPRNG. It MUST NOT be logged, persisted, or
  placed on any pasteboard/clipboard, and MUST be zeroed on window close (success, expiry, or attempt
  exhaustion). The QR window is excluded from screen capture where the OS allows it (implementation
  detail owned by E14-11).
- **Concurrency.** At most one pairing-candidate connection is processed at a time
  (`docs/planning/decisions.md` D-18; §1's verify callback). A second unknown client certificate
  arriving while one candidate is already in flight MUST be rejected in the verify callback itself,
  before any pairing message is ever processed, and MUST NOT burn one of the 3 attempts: only a
  `PairRequest` (valid or not), a wrong payload arriving after the hellos (§ Frame order, below), or a
  candidate connection closing before `PairAccepted` for any other reason (next bullet) burns an
  attempt; a rejection inside the verify callback itself never does.
- **A pairing-candidate connection burns one attempt whenever it closes for any reason other than
  `PairAccepted`** (`docs/planning/decisions.md` D-70) — including a `VersionHello`-deadline miss
  (`PROTOCOL_TIMEOUT`, §5 row 8; this is the one place that close code does burn a pairing attempt),
  the peer closing the connection, or a transport error. The candidate slot (§1's verify callback) is
  occupied from the moment the verify callback accepts the unknown certificate until that connection
  closes, so an attacker who occupies the slot and then goes silent — rather than sending a wrong
  payload or missing the 10 s `PairRequest` deadline — still burns the attempt and frees the slot for
  the legitimate phone, instead of denying it for the rest of the 120 s window at no cost. Each
  candidate connection burns **at most one** attempt in total, regardless of how many of the events
  above it triggers before closing — e.g. a `BAD_PROOF` rejection followed immediately by the
  connection dropping is one candidate closing once, not two separate attempts.

### Dialing the QR addresses (phone side)

The phone MUST attempt each literal address in the QR `a` field in order, with a 3 s connect timeout
per address (`docs/planning/decisions.md` D-68). A connect timeout on one address MUST advance to the
next address in the list; if every address times out, the pairing attempt MUST fail
(`Failed(AllAddressesUnreachable)`, E14-05) without the phone ever having reached the point of
completing a TLS handshake — and therefore without ever occupying a Mac-side pairing-candidate slot —
for an address it never reached.

### Frame order on a pairing-candidate connection

1. Both sides exchange `VersionHello` (§6, `#versioning-and-capability-negotiation`) — exactly as on
   any other connection, this is the only legal payload before the exchange completes (§3, §6).
2. Once both hellos are exchanged, the Mac MUST send `PairChallenge { challenge }` (§1,
   `#handshake-and-tls-profile`) as the very next `CONTROL` frame, before any other payload, without
   waiting on anything from the phone.
3. The phone MUST reply with exactly one `PairRequest { deviceInfo, proof }` within 10 s of the hello
   exchange completing (§10, `#timeouts-connection-limits-and-resource-caps`, E01-22). The Mac's
   `PairChallenge` send is expected to be near-instantaneous, so this single 10 s deadline covers both
   the challenge and the request; a `PairRequest` arriving more than 10 s after the hellos complete is
   rejected exactly as case 4 below.
4. Any of the following closes the connection with `PAIRING_FAILED` (§5) and burns one of the 3
   attempts: a payload other than the expected next message in this sequence (including a second
   `PairChallenge`, a `PairRequest` arriving before `PairChallenge`, a duplicate `PairRequest`, or any
   other payload type — local reason `MALFORMED`); or the phone failing to send any `PairRequest`
   within the 10 s deadline (local reason `TIMEOUT` — the one case where a §10 deadline maps to
   `PAIRING_FAILED` rather than `PROTOCOL_TIMEOUT`, per §5). `Heartbeat` frames are exempt from this
   rule in both directions: §7's (`#heartbeat`) liveness contract applies to a pairing-candidate
   connection exactly as to any other control connection (the owner may take up to 120 s to act on
   the confirmation dialog, § Mutual confirmation, below, so the Mac's 15 s idle `Heartbeat` MUST NOT
   be treated as a wrong payload here), and a `Heartbeat` received at any point on a pairing-candidate
   connection is never a pairing failure — it remains subject only to §10's `CONTROL` rate caps
   (`docs/planning/decisions.md` D-69).
5. Once the Mac sends `PairAccepted` (§ Mutual confirmation, below), the connection is an ordinary
   trusted session: no further pairing-only message is legal on it.
6. After sending `PairRequest`, the phone MUST wait up to 120 s — the same duration as the pairing
   window's own expiry, § Pairing window, above — for either `PairAccepted` or `PairRejected`; if
   neither arrives within that time, or the connection ends first, the phone MUST treat this pairing
   attempt as failed and MUST NOT assume any pairing outcome (`Failed(Timeout)` /
   `Failed(ConnectionLost)`, E14-05).

### Proof computation

- `macSpkiDer` and `phoneSpkiDer` are both 91-byte uncompressed P-256 `SubjectPublicKeyInfo` DER (§1).
  `macSpkiDer` is the SPKI of the Mac's own certificate (its SHA-256 equals the QR `fp` the phone
  scanned); `phoneSpkiDer` is taken from the client certificate seen on *this* TLS handshake — never
  from any field of the `PairRequest` body — so a `PairRequest` can never claim a different key than
  the one that actually authenticated this connection.
- `LP(x) = u16be(len(x)) || x`: a 2-byte big-endian length prefix followed by the raw bytes (this
  document's default big-endian convention, Conventions).
- `transcript = ASCII("tandem-pair-v1") || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)`, where `cb` is
  this session's channel-binding value (§1) — exactly the 32 bytes of the `PairChallenge` the Mac sent
  on this connection (§ Frame order, above).
- `proof = HMAC-SHA256(secret, transcript)`, where `secret` is the 16-byte pairing secret from the QR
  `s` field.
- The Mac MUST recompute `proof` using its own `macSpkiDer`, the `phoneSpkiDer` it observed on this
  connection's handshake, and the `cb` it itself generated and sent, then compare it against
  `PairRequest.proof` in constant time (invariant 6). A mismatch MUST be rejected, local reason
  `BAD_PROOF`, burning one attempt.
- This formula — including the `LP` width/byte order, the 91-byte SPKI DER requirement, and the `cb`
  input defined in §1 — supersedes the raw-concatenation proof formula in `docs/PRD.md` F-2.1 step 3
  (`docs/planning/decisions.md` D-14, D-40): this document is normative.

### Confirmation code

- `code = (u32be(first 4 bytes of HMAC-SHA256(secret, ASCII("tandem-pair-code-v1") ||
  LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)))) mod 1000000`, rendered zero-padded to exactly 6
  digits (e.g. `007042`, shown as `007 042`) on both the Mac dialog and the phone.
- Both sides compute this independently from the same `secret`, `macSpkiDer`, `phoneSpkiDer` and `cb`
  already used for `proof` above; no separate message carries the code itself.
- Evil-QR detection does **not** rely on `cb` differing across a relay: an attacker relaying between
  the phone and the Mac (terminating TLS separately with each) can simply forward the challenge value
  it receives on one session as the `PairChallenge` it sends on the other, so `cb` can be identical on
  both sides of a relay (§1, Channel binding). What actually differs is `macSpkiDer`/`phoneSpkiDer`:
  the attacker must use its own key on at least one side of the relay — it holds neither the real
  Mac's nor the real phone's private key, which `CertificateVerify` enforces (§1, Verify-callback
  algorithm) — so the SPKI pair, and therefore `code`, differs between the session the phone sees and
  the session the Mac sees, even when `cb` is identical on both. This SPKI-pair difference is the
  evil-QR detection property the owner is asked to check (`docs/planning/decisions.md` D-16, D-71,
  AC-20).
- `deviceInfo.displayName`/`.model` (both attacker-controlled, sanitized per §11 before display) are
  never an input to `code` or `proof`, and are never the basis of the pairing decision.

### Mutual confirmation

- The Mac shows the owner the phone's (sanitized, §11) device name and model, and the 6-digit code,
  with two actions: Pair, and Don't Pair. Both the dialog's default button and the Escape key MUST map
  to Don't Pair (`docs/planning/decisions.md` D-16).
- The Mac MUST NOT send `PairAccepted` until the owner explicitly clicks Pair. An explicit owner
  decline (clicking Don't Pair, pressing Escape, or closing the window) is a deliberate, terminal
  decision, not a retriable proof failure: the Mac MUST send `PairRejected { reason = REJECTED_BY_OWNER
  }` (§ PairRejected wire collapse, below) and close with `PAIRING_FAILED`, and MUST destroy the
  secret and close the window entirely (as a successful pairing does), rather than merely burning one
  of the 3 attempts and leaving the window open for a retry.
- If the candidate connection closes (peer disconnect, transport error, or the window/attempt budget
  being exhausted, § Pairing window, above) while this confirmation dialog is still pending, the Mac
  MUST dismiss the dialog and MUST NOT commit trust; clicking Pair afterward, on a connection that is
  no longer open, commits nothing (`docs/planning/decisions.md` D-73). A pending dialog is resolved
  only by an owner action (Pair or Don't Pair) taken while the underlying connection is still open.
- On Pair, the Mac commits the phone's SPKI to its trust store and sends `PairAccepted`.
- The phone, on receiving `PairAccepted`, MUST show the owner the same 6-digit code and the
  (sanitized) Mac name, with two actions: "Codes match" and Cancel. The phone MUST commit the Mac's
  SPKI pin only after both (a) `PairAccepted` has been received and (b) the owner taps "Codes match"
  (`docs/planning/decisions.md` D-16, AC-20) — receiving `PairAccepted` alone is never sufficient.
- On phone-side Cancel, or a 120 s timeout without the owner tapping "Codes match", the phone MUST
  send `Revoke {}` over this connection (which is, by this point, an ordinary trusted session from the
  Mac's perspective — the Mac already committed and accepted it) and MUST commit nothing to its own
  trust store. From the phone's perspective pairing never happened, even though the Mac-side trust
  record exists, with a `lastSeen` time and revocable, until that `Revoke` is processed (dangling-record
  residual, `docs/threat-model.md` §4.3).

### `PairRejected` wire collapse

`PairRejected.reason` (`pairing.proto`, E01-11) carries on the wire exactly one of two values:
`REJECTED_BY_OWNER` (the Mac-side decline above) or `PAIRING_UNAVAILABLE` (every other local rejection
reason a connection can actually receive: `EXPIRED`, `BAD_PROOF`, `MALFORMED`; local reason `TIMEOUT`
closes without sending a `PairRejected` at all, since no `PairRequest` was ever received to reject it —
`TIMEOUT` is the one `PAIRING_FAILED` local reason with no wire signal, exactly like `MALFORMED_FRAME`,
`CREDIT_VIOLATION`, `TICKET_REJECTED`, `PROTOCOL_TIMEOUT` and `LIMIT_EXCEEDED` in §5
(`docs/planning/decisions.md` D-72). No
wire value distinguishes a bad proof from an expired window from a malformed request
(`docs/planning/decisions.md` D-17) — this denies an attacker any oracle for which specific defense
stopped their attempt. Every case above also closes the pairing-candidate connection with the
`PAIRING_FAILED` close code (§5, `#errors-and-close-codes`).

`attemptsExhausted` is a distinct, **local-only** window state (§ Pairing window, above), not a
`PairRejected`/`PAIRING_FAILED` local reason: no connection ever receives it, because the window
already closes as soon as the 3rd failed attempt's own rejection (one of `EXPIRED`, `BAD_PROOF`,
`MALFORMED`, or `TIMEOUT`) is sent, and a subsequent 4th connection attempt is rejected in the verify
callback (§1) — with no open pairing window, it never becomes a pairing candidate at all, so it is
never a `PAIRING_FAILED` close and never carries a `PairRejected`.

---

## Framing and envelope

*(E01-03 · PRD F-3.2 · AC-07 · no invariant references)*

This section defines the byte-level frame format used on every mTLS connection (control, F-3.1,
and media, F-3.3) once the TLS handshake has completed, and the wire-contract shape of the
`Envelope` that every frame carries. The `Envelope` protobuf message itself (field numbers, types)
is defined in `protocol/proto/tandem/v1/envelope.proto` (E01-10); this section is normative for
its shape and every receiver's required behavior.

### Frame format

A frame is:

```
frame = length_prefix envelope_bytes
length_prefix = u32 big-endian
envelope_bytes = length_prefix octets, a serialized Envelope message
```

- `length_prefix` is an unsigned 32-bit big-endian integer counting the number of `Envelope` bytes
  that follow — that is, it excludes the 4 prefix bytes themselves.
- The maximum permitted value of `length_prefix` is 1 048 576 (1 MiB, 2^20).
- A receiver MUST compare `length_prefix` against the 1 MiB maximum before allocating any buffer
  sized from it. Allocating (or reserving) a buffer using an unchecked, attacker-supplied length is
  forbidden regardless of how large the underlying transport buffer already is.

### Envelope fields

`Envelope` carries, at the wire-contract level:

- `channel` — identifies which of the nine F-3.2 channels (`CONTROL`, `NOTIFY`, `CLIPBOARD`,
  `FILES`, `SMS`, `CONTACTS`, `CALLS`, `INPUT`, `STATUS`; enumerated normatively in §4,
  `#channels-and-flow-control-credits`) this frame belongs to.
- `seq` — an unsigned 64-bit counter (`uint64`), maintained independently per channel and per
  direction (i.e. each side of a connection keeps its own outgoing counter per channel). The first
  frame a side sends on a given channel carries `seq = 1`; each subsequent frame that side sends on
  that same channel increments its own counter by exactly 1. `seq = 0` is never valid on the wire
  (§ Sequence and acknowledgement violations, below). Counters on different channels, and the two
  directions' counters on the same channel, are independent of one another.
- `ack` — the highest `seq` value received on that channel, in contiguous order, from the peer.
  Before any frame has been received on that channel in that direction, `ack` is 0, meaning
  nothing has been received yet (unambiguous, since `seq` is never 0 on the wire). `ack` MUST NOT
  advance past a gap: if a receiver has seen `seq` 1 and 3 but not yet 2, `ack` for that channel
  stays at 1 until `seq = 2` arrives, at which point it becomes 3. This is the contract the E11
  channel multiplexer (E11-05, E11-06) implements against.
- `payload` — a `oneof` carrying exactly one typed application message, whose set of legal types is
  fixed by the protocol version in effect on the connection (E01-06).

### Rejection cases

Each of the following is a framing-level protocol violation. On detecting any of them, a receiver
MUST close the connection with close code `MALFORMED_FRAME` (§5, `#errors-and-close-codes`). The
specific case is a local diagnostic reason only: it is never sent on the wire and it is never a
separate close code (`docs/planning/decisions.md` D-13 — no parser oracle on the wire).

| Case | Local reason | Trigger |
|---|---|---|
| Oversize | `TOO_LARGE` | `length_prefix` > 1 048 576 |
| Bad length | `BAD_LENGTH` | `length_prefix` == 0 |
| Truncated | `TRUNCATED` | the connection's byte stream ends via an orderly close (EOF, or a TLS `close_notify`) after at least 1 byte of a new frame — the length prefix or the envelope bytes — has arrived, but before that frame is complete. A TCP reset (RST) is a transport-layer error, not a framing rejection: it MUST be reported by the transport layer as a connection error, never as `MALFORMED_FRAME`/`TRUNCATED` (E11-02, E11-04). |
| Malformed | `DECODE_FAILED` | the `length_prefix` bytes received fail to decode as a well-formed `Envelope` protobuf message |
| Unknown channel | `UNKNOWN_CHANNEL` | `channel` is not one of the nine values enumerated in §4, including the reserved `CHANNEL_UNSPECIFIED = 0` value |
| Unknown payload | `UNKNOWN_PAYLOAD_TYPE` | the `oneof payload` is unset, or set to a payload type this receiver's protocol version does not define (AC-11) |

A receiver MUST check `length_prefix` against the 1 MiB maximum (the oversize case) before reading
or allocating anything for the payload; in particular, an oversize `length_prefix` MUST be
rejected using only the 4 prefix bytes, without waiting for or buffering any of the (attacker
supplied, arbitrarily large) claimed payload. An orderly close (EOF or TLS `close_notify`) that
arrives exactly at a frame boundary — zero bytes into a new frame — is a normal, non-error
connection close, not a `TRUNCATED` violation.

Before both sides have exchanged `VersionHello` (§6, E01-06) on the **control connection**, the
only legal payload on that connection is `VersionHello` itself; any other payload arriving first
MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`, closing with `MALFORMED_FRAME`. On the **media
connection**, the first frame MUST be `MediaHello` (§9); any other first payload MUST be rejected
as `UNKNOWN_PAYLOAD_TYPE` (closing with `MALFORMED_FRAME`), per E60-02/E60-03.

### Sequence and acknowledgement violations

Regression is defined relative to the **ack watermark**, not relative to the highest `seq` value
ever seen: the ack watermark for a channel and direction is the current value of `ack` as defined
under Envelope fields above (the highest `seq` received in contiguous order so far, 0 before
anything has arrived). A `seq` value above the watermark that has not been seen before is never a
violation, even if it is lower than the highest `seq` received so far on that channel — that is
exactly the gap-fill case, and it advances `ack` past that value and past any further
already-received, now-contiguous values.

A receiver MUST close the connection with close code `MALFORMED_FRAME` (local reason
`SEQ_REGRESSION`) on receiving, for any channel:

- a frame with `seq = 0` — there is no valid frame numbered zero, since the first frame a side
  sends on a channel carries `seq = 1`;
- a frame whose `seq` is less than or equal to the current ack watermark for that channel (it
  duplicates or falls behind a value already folded into `ack`); or
- a frame whose `seq` exactly repeats a value already received above the watermark but not yet
  folded into `ack` (a duplicate of a frame still held back by an earlier gap).

Worked example (single channel, one direction; arrival order left to right):

| `seq` arrival order | What happens | `ack` after each arrival |
|---|---|---|
| 1, 3, 2 | all three accepted: 1 sets the watermark; 3 is a gap, held; 2 fills the gap, which then folds in the already-received 3 | 1, 1, 3 |
| 1, 2, 2 | 1 and 2 accepted; the second 2 is at the watermark (2 ≤ 2) | 1, 2, **fatal** |
| 1, 3, 1 | 1 accepted; 3 is a gap, held; the second 1 is at or below the watermark (1 ≤ 1) | 1, 1, **fatal** |

A receiver MUST also close the connection with close code `MALFORMED_FRAME` (local reason
`SEQ_REGRESSION`) on receiving, for any channel, an `ack` value greater than the highest `seq` this
side has itself sent on that channel so far — the peer is acknowledging a frame that was never
sent.

Sequence numbers are a strict per-channel, per-direction contract (E11-05/E11-06 acceptance: "a
repeated or regressing seq triggers the E01-03-defined behaviour"); a sender that would otherwise
need to send a `seq` at or below the watermark, or repeat an already-received above-watermark
value, has no valid frame to send and MUST NOT send one. This `SEQ_REGRESSION` local reason, its
watermark-relative definition, and its assignment to the existing `MALFORMED_FRAME` close code
rather than a new one, are recorded in `docs/planning/decisions.md` D-57.

### No fragmentation on the control connection

On the control connection, an `Envelope` is never split across more than one frame: every frame's
`length_prefix` bytes are exactly one complete, self-contained `Envelope`. A receiver MUST buffer
at most one partial (not yet fully received) frame per connection, and that partial frame is at
most 1 048 576 + 4 = 1 048 580 bytes.

The only fragmentation mechanism anywhere in this protocol is the media-connection `MediaFrame`
access-unit fragmentation rule owned by §12 (`#media-frame-semantics`, E61-01,
`docs/planning/decisions.md` D-26): an encoded access unit larger than 960 KiB is split into at
most 8 fragments of at most 960 KiB each, sharing one `pts`, contiguous and in index order: 8
fragments of at most 960 KiB each reassemble to at most 7.5 MiB (8 × 960 KiB = 7 680 KiB = 7.5 MiB)
by construction, within the 8 MiB media access-unit cap of §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22). That rule applies only to `MediaFrame` on
the media connection; it does not change anything stated above for the control connection, and it
does not raise the 1 MiB per-frame maximum defined in this section, which still bounds the size of
each individual fragment's frame.

---

## Channels and flow-control credits

*(E01-04 · PRD F-3.2 · UC-08, UC-09, UC-14, UC-15, UC-17, AC-11, AC-19 · invariant 2)*

This section enumerates the closed set of channels a `channel` field (§3, `#framing-and-envelope`)
may name, and defines the credit-based flow-control algorithm that keeps one channel's traffic from
starving another's — in particular, so a large FILES transfer cannot delay a NOTIFY frame.

### Channel enumeration

`Channel` numeric values are frozen once released, exactly as the close-code numeric IDs in §5: an
implementation or `.proto` file MUST NOT renumber or reuse a channel value once it ships (E01-10).
`CHANNEL_UNSPECIFIED` is reserved and MUST NOT be assigned to any channel, consistent with `0` being
reserved across every enum in this protocol (`Channel`, `PairRejected.reason`, close codes).

| ID | Name | Carries (informative; see E01-14 for the authoritative future-domain mapping) |
|---|---|---|
| 0 | `CHANNEL_UNSPECIFIED` | Reserved. Never a valid value on the wire (§3, `UNKNOWN_CHANNEL`). |
| 1 | `CONTROL` | `VersionHello`, `Heartbeat`, `CreditGrant`, `MediaTicketGrant`, pairing and rotation messages. |
| 2 | `NOTIFY` | Notification mirroring (F-5.1–F-5.4). |
| 3 | `CLIPBOARD` | Clipboard sync (F-6.1–F-6.3). |
| 4 | `FILES` | File transfer and the photo browser (F-7.1–F-7.4; see decision below). |
| 5 | `SMS` | SMS read/sync/send (F-8.1, F-8.2). |
| 6 | `CONTACTS` | Contacts sync (F-8.3). |
| 7 | `CALLS` | Call control (F-8.4). |
| 8 | `INPUT` | Remote input events (F-9.3). |
| 9 | `STATUS` | Device status, `Ring`/`RingStop` (F-4.3, F-4.4). |

This channel set is closed and exhaustive: the nine values above, plus the reserved
`CHANNEL_UNSPECIFIED = 0`, are the only channel values this version of the protocol ever defines.
There is no tenth `PHOTOS` channel: the photo browser's paged listings, thumbnail requests and
thumbnail results (F-7.4) are `FILES`-channel payloads, sharing `FILES`'s credit ledger with any
in-flight file transfer (`docs/planning/decisions.md` D-01; E41-01). A sender interleaving a large
file transfer with photo-browser traffic on `FILES` MUST round-robin its outgoing `FILES` frames per
logical stream (one transfer, or one browse/thumbnail request, is one stream) rather than fully
draining one stream before starting another, so a multi-gigabyte transfer cannot itself starve a
thumbnail response on the same channel (E41-01).

No channel value, message type, or payload exists anywhere in this protocol for debugging, echo,
loopback, or test-only purposes, in either a debug or a release build: debug and release builds
speak an identical protocol (`docs/planning/decisions.md` D-02). A payload type this receiver's
protocol version does not define — including any such hypothetical debug-only type — is rejected as
`UNKNOWN_PAYLOAD_TYPE` under the existing `MALFORMED_FRAME` close code (§3), never accepted or
specially recognized (AC-11).

### Credit accounting

The credit unit for every channel this section's ledger applies to is whole frames: one credit
permits the sender to transmit exactly one `Envelope` frame on that channel, independent of the
frame's payload size (up to the 1 MiB maximum of §3). This matches the unit `FileChunk` senders
already reason in (E40-03/E40-04: "one credit grant releases exactly the granted number of chunks").

Every channel except `CONTROL` (the exemption is defined below) has its own credit ledger, tracked
independently by each side for its own outgoing direction:

- **Per-channel cap.** For each of the eight feature channels (`NOTIFY`, `CLIPBOARD`, `FILES`, `SMS`,
  `CONTACTS`, `CALLS`, `INPUT`, `STATUS`), a receiver chooses its own cap for that channel: the
  maximum credit it will ever have outstanding to its peer on that channel at one time. A chosen cap
  MUST NOT exceed 64 credits; a receiver MAY choose a smaller cap for a given channel (for example, a
  lower `FILES` cap on a memory-constrained phone) to bound its own memory use. Because a frame is at
  most 1 MiB (§3), a channel whose cap is `n` credits bounds that channel's receive buffering
  (decoder → consumer, below) at `n` × 1 MiB.
- **Initial grant.** A new ledger for a feature channel starts with a balance equal to that channel's
  chosen cap.
- **Consume.** A credit is returned to the sender's balance — i.e. counted toward the replenishment
  trigger below — only once the channel's application-level consumer has actually taken the
  corresponding frame out of the receiver's decoder→consumer buffer, not merely once the frame has
  been decoded off the wire. This is what makes the cap a real bound on buffering: a stalled consumer
  stops replenishment, which in turn stops the sender once its outstanding credit is exhausted, so
  the buffer between decoder and consumer for that channel never holds more than `cap` frames (the
  bound stated above).
- **Replenishment.** `CreditGrant { channel, amount }` is the replenishment message (it rides the
  `CONTROL` channel like `Heartbeat` and `VersionHello`, defined in `control.proto`, E01-12, since it
  must never itself be subject to the credit system it manages). A receiver MUST send exactly one
  `CreditGrant` for a channel each time that channel's outstanding grant to its peer is consumed
  (per the rule above) down to half of the channel's cap or fewer — i.e. at the moment cumulative
  consumption since the last grant (or since the initial grant, if none has been sent yet) first
  crosses the halfway point, not on every frame consumed after that. `amount` MUST restore the peer's
  balance to exactly the channel's cap, never above it. The trigger then re-arms against this new,
  fully-replenished balance, so it fires again the next time consumption crosses that channel's
  halfway point.
- **Grant beyond the cap.** A `CreditGrant.amount` that would take the receiving side's own balance
  for that channel above its chosen cap is a protocol violation, not a local bookkeeping adjustment:
  the credit ledger MUST report the overflow rather than silently absorbing it, and the multiplexer
  MUST close the connection with the close code `CREDIT_VIOLATION` (§5, `#errors-and-close-codes`,
  row 4) on receiving it. Clamping such a grant to the cap and continuing, instead of closing, would
  leave the receiver silently unable to ever use credit it was told it has — effectively deadlocking
  that channel — which is why an over-cap grant closes rather than clamps.
- **Sender obligation.** A sender MUST NOT transmit a frame on a feature channel while its remaining
  credit for that channel is zero; it pauses that channel until a `CreditGrant` restores credit.
- **Violation.** A peer that transmits on a feature channel past the credit it was actually granted —
  the same close condition as an over-cap grant, above — MUST cause the receiver to close the
  connection with the close code `CREDIT_VIOLATION`. A receiver MUST NOT silently drop an
  over-credit frame instead of closing.
- **`CreditGrant` naming an ineligible channel.** A `CreditGrant.channel` naming `CONTROL`,
  `CHANNEL_UNSPECIFIED`, or any value outside the nine defined channels MUST be rejected with the
  close code `MALFORMED_FRAME`, local reason `UNKNOWN_CHANNEL` (§3) — `CONTROL` carries no credit
  ledger to grant against (below), and the other two values never name a real channel. A
  `CreditGrant.amount` of 0 is well-formed and MUST be treated as a no-op (ignored, not an error and
  not a violation).

### CONTROL is exempt from credit accounting

`CONTROL` carries no credit ledger at all and is exempt from every rule above: control and heartbeat
traffic (§7, `#heartbeat`) MUST NOT be backpressured by the credit system, both because it must never
be starved and because `CreditGrant` itself rides `CONTROL` — a credit-gated `CONTROL` channel could
deadlock. In its place, `CONTROL` has the separate, fixed-rate caps of §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22): the phone answers at most one `Heartbeat`
per second, dropping faster ones silently with no reply, no error and no close
(`docs/planning/decisions.md` D-60); and non-`Heartbeat` `CONTROL` frames from a peer are capped at
60 per second per session, exceeding which closes the connection with `LIMIT_EXCEEDED`
(`docs/planning/decisions.md` D-61).

---

## Errors and close codes

*(E01-05 · PRD F-3.2 · AC-04, AC-07, AC-13 · invariant 5)*

This section is the single canonical enumeration of protocol-level close codes. Every other
section, `.proto` file, and test vector that needs to name a fatal protocol condition MUST use one
of the names in the table below; no other part of this document or the codebase may introduce a
new close code outside this table.

**Invariant 5 (fail closed with a visible error) governs every row in this table.** A close code
MUST NOT trigger a plaintext, reduced-security, or unauthenticated retry of any kind (invariant 2):
closing is always the end of that connection attempt, never a downgrade. A `PairRejected.reason`
of `UNSPECIFIED` (0) or any value outside `{REJECTED_BY_OWNER, PAIRING_UNAVAILABLE}` MUST be
treated as fatal and mapped locally to `PAIRING_FAILED` with generic pairing-failed text; it MUST
NOT be treated as non-fatal and MUST NOT be presented as revealing a specific reason. The same rule
applies to any wire-carried code a future version of this protocol adds: a value the receiving
implementation does not recognize MUST be treated as fatal, MUST produce a generic
connection-error message, and MUST NOT be guessed at.

### Pre-authentication closes are not surfaced per connection

The listening side (the Mac) MUST NOT surface a per-connection UI notification for a close on a
connection whose peer has not yet passed the TLS pin check (§1, E01-01) — for example, one of many
unsolicited connection attempts closed with `PIN_MISMATCH`, `PROTOCOL_TIMEOUT`, or `LIMIT_EXCEEDED`
while listening, before that peer's key was ever recognized. Each such close MAY be counted in an
aggregate, non-blocking counter (e.g. "N rejected connections today"), but MUST NOT pop a dialog or
alert per attempt: doing so would let an unauthenticated network attacker drive the Mac's UI
(AC-13, `docs/planning/decisions.md` D-59).

Once a peer has passed the pin check — even if the connection then fails a later, post-pin step
such as the `VersionHello` comparison or the hello-stage deadline — its close MAY instead be shown
in an already-visible status area rather than a popped dialog (E12-10
`failClosedErrorScenario_menuOpened_showsVersionMismatchText`): a pinned peer's `VERSION_MISMATCH`
or hello-stage `PROTOCOL_TIMEOUT` is about a device the user already recognizes, not network noise,
and a status-area indicator satisfies the "MUST be shown in the UI" requirement on such a row.
`VERSION_MISMATCH` in particular can only ever occur once the pin check has passed (`VersionHello`
is exchanged after TLS completes), so the pre-pin-check scoping above never applies to it.

Everywhere this section says a close code's text "MUST be shown in the UI", that requirement
applies to (a) the dialing side (the phone), for which each connection attempt — a control-session
dial, or a media-session dial made concurrently with an already-open control session (§9, E60-02)
— is the direct result of a single user-visible action, and (b) either side when the close tears
down an already-authenticated, Ready session or any connection whose peer already passed the pin
check. It does not require the Mac to surface every pre-pin-check connection attempt from the
network.

### Local reason vs. wire code

A close code is always determined locally by whichever side detects the fault, and is always the
value used for that side's logs, its local UI error mapping, and the `closeCode` field asserted by
this protocol's test vectors (E01-16, E01-19). Several close codes additionally group a set of
finer-grained local reasons that are diagnostic only and are never sent to the peer in any form
(`docs/planning/decisions.md` D-13, D-17): `MALFORMED_FRAME` (reasons `TOO_LARGE`, `BAD_LENGTH`,
`TRUNCATED`, `DECODE_FAILED`, `UNKNOWN_CHANNEL`, `UNKNOWN_PAYLOAD_TYPE`, `SEQ_REGRESSION`,
`FRAGMENT_VIOLATION`, §3, §12), `PAIRING_FAILED` (reasons `EXPIRED`,
`BAD_PROOF`, `REJECTED_BY_OWNER`, `TIMEOUT`, `MALFORMED`, §2 — `attemptsExhausted` is a related but
distinct *local window state*, never itself a connection's close reason, see §2 `PairRejected` wire
collapse), and `TICKET_REJECTED` (reasons `MISSING`, `REUSED`, `EXPIRED`, `OTHER_SESSION`, §9).

There is no dedicated close-notice message in this version of the protocol: no message type
carries a generic `closeCode` field to the peer. A close code is inferred by the peer only through
one of four existing signals:

1. **`PairRejected.reason`** — sent immediately before the close on a pairing-candidate connection
   (§2, E01-11), collapsing four of the five `PAIRING_FAILED` local reasons above per the rule below.
   The fifth, `TIMEOUT`, sends no `PairRejected` at all (see below and §2's `PairRejected` wire
   collapse) — it is grouped with the five "no signal" close codes in the next paragraph instead.
   (`attemptsExhausted` is not in this count at all: it is a local window state, never a connection's
   own close reason, § above.)
2. **`Revoke`** — received on an already-trusted session, the receiver deletes its trust record for
   the sender (the peer authenticated on that session) and closes that session with `REVOKED` (§2,
   E01-11; `docs/planning/decisions.md` D-23).
3. **The `VersionHello` comparison itself** — `VERSION_MISMATCH` needs no separate signal: each side
   locally compares the peer's advertised protocol major version, already exchanged per §6
   (E01-06), against its own.
4. **A TLS handshake-failure alert** (`certificate_unknown` / `bad_certificate`) on an ordinary,
   non-pairing-candidate dial — the dialing side maps the alert it receives to `PIN_MISMATCH`, or,
   if it had previously pinned that peer, to `REVOKED` ("no longer paired", E12-16; see row 7
   below). There is no persistent "revoked" record on the rejecting side: deleting a trust record
   removes all memory of the peer (`docs/planning/decisions.md` D-23), so the rejecting side cannot
   distinguish an unrecognized key from a previously-revoked one and always produces
   `PIN_MISMATCH`. This mapping does not apply on a **pairing-candidate** dial (the QR flow, §2):
   E12-16 scopes the `PIN_MISMATCH`/`REVOKED` alert mapping to non-pairing connections. If the
   phone's own pin check against the QR `fp` has already passed (the Mac's identity is not in
   question) and a handshake-failure alert then arrives, the phone maps it to `PAIRING_FAILED`
   (a generic local reason — the pairing window closing, being full, or otherwise unavailable)
   rather than `PIN_MISMATCH`.

No other close code in the table below has any wire signal at all: for `MALFORMED_FRAME`,
`CREDIT_VIOLATION`, `TICKET_REJECTED`, `PROTOCOL_TIMEOUT`, and `LIMIT_EXCEEDED`, the peer observes
only that the connection closed, with nothing to distinguish which of these five occurred. The same
is true of `PAIRING_FAILED`'s `TIMEOUT` local reason specifically (the `PairRequest` 10 s deadline,
§2): no `PairRequest` was ever received for the Mac to reject, so no `PairRejected` is sent and the
peer again observes only a closed connection (`docs/planning/decisions.md` D-72). This is a deliberate
generalization of "no parser oracle on the wire" (`docs/planning/decisions.md` D-13) beyond
`MALFORMED_FRAME` to every close code — and every local reason within a close code — that has no
signal above. A future protocol revision MAY add a wire-transmitted signal for one of these; until it
does, the peer MUST NOT infer any of them from anything other than the four signals above.

`PairRejected.reason` collapses four of the five `PAIRING_FAILED` local reasons onto exactly two wire
values: local reason `REJECTED_BY_OWNER` maps to wire value `REJECTED_BY_OWNER`; `EXPIRED`,
`BAD_PROOF` and `MALFORMED` each map to wire value `PAIRING_UNAVAILABLE`. The
fifth local reason, `TIMEOUT`, sends no `PairRejected` at all (above) — the connection simply closes,
since no `PairRequest` was ever received to reject. The rejecting Mac MAY show its own owner the
specific local reason in its pairing UI (that detail never leaves the Mac); the rejected phone MUST
derive its pairing-failure text only from whichever of the two wire values it received (or, for
`TIMEOUT`, from the bare close with no `PairRejected`), never from an assumption about which local
reason caused it.

### Close-code table

Numeric IDs are frozen once released: an implementation, `.proto` file, or test vector MUST NOT
reuse or renumber an ID once it ships. IDs below are assigned in the order each code was ratified
(review cycle 3 for IDs 1–7, cycle 4 for IDs 8–9; `docs/planning/decisions.md` D-13, D-20). ID `0`
is reserved and MUST NOT be assigned to any code, so that a future shared `CloseCode` enum can use
it as an explicit `UNSPECIFIED` default consistent with every other enum in this protocol
(`Channel`, `PairRejected.reason`).

| ID | Name | Occurs when (triggering condition) | User-visible behavior |
|---|---|---|---|
| 1 | `VERSION_MISMATCH` | The `VersionHello` protocol major version fields exchanged per §6 differ (E01-06). | Security-relevant: MUST be shown in the UI — this always occurs after the peer's pin check has passed (`VersionHello` is only exchanged after TLS completes), so the pre-pin-check scoping above never suppresses it; a status-area indicator satisfies this requirement (E12-10). Text MUST name the version mismatch specifically (e.g. "this Mac/phone needs an app update"), never a generic error. |
| 2 | `PIN_MISMATCH` | The TLS verify callback (§1, E01-01) computes a peer SPKI fingerprint that does not match the trust store: on the Mac, this fires outside an open pairing window (during an open window an unrecognized key is accepted only for the pairing exchange, §2); on the phone, which has no inbound connections at all (invariant 4) and therefore never opens a pairing window, this fires on every connection whose peer key does not match the trust-store pin or, during pairing, the QR `fp`. | Security-relevant: MUST be shown in the UI (subject to the pre-pin-check scoping above), not only logged (UC-05). Text MUST be specific ("this device's identity changed / is not trusted"), never a generic error, and MUST NOT suggest retrying without re-pairing. |
| 3 | `MALFORMED_FRAME` | Any framing-level rejection in §3 (oversize, bad length, truncated, decode failure, unknown channel, unknown payload type, seq/ack regression), or a §12 `MediaFrame` fragmentation violation on the media connection — index gap, fragment-count change, count greater than 8, interleaving with another `pts`, or a reassembled size over 8 MiB (local reason `FRAGMENT_VIOLATION`, `docs/planning/decisions.md` D-26). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |
| 4 | `CREDIT_VIOLATION` | A sender transmits on a channel with zero remaining credit, or a receiver's outstanding grant would exceed its cap (§4, E01-04). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |
| 5 | `PAIRING_FAILED` | Any pairing-window rejection in §2 (expired, bad proof, rejected by owner, malformed request), including the `PairRequest` 10 s deadline of §10/E01-22 (local reason `TIMEOUT`), which burns one pairing attempt like any other failed attempt (E01-02, E14-02). A 4th candidate connection, once the 3rd failed attempt has already closed the window (local window state `attemptsExhausted`, §2), is refused in the verify callback (§1) before it ever becomes a pairing candidate — it is never a `PAIRING_FAILED` close. | MUST be shown in the pairing UI (it is the direct result of a user-initiated pairing attempt); text MUST NOT distinguish which of the five local reasons occurred. |
| 6 | `TICKET_REJECTED` | The media connection's `mediaTicket` (§9, E01-09) is missing, already consumed (reused), expired, or was issued to a different control session's peer. | Generic connection-error message on the media connection only; MUST NOT affect or close the control session, and MUST NOT be presented as a pin or version problem. |
| 7 | `REVOKED` | This side processes a valid `Revoke` on an already-trusted session and deletes its trust record for that peer (§2, E01-11; `docs/planning/decisions.md` D-23), closing that session with `REVOKED`; or this side dials a peer that no longer recognizes its client key and the resulting TLS alert is mapped, per E12-16, to `REVOKED` — but only if this side had previously pinned that peer (otherwise the same alert maps to `PIN_MISMATCH`, since there is no persistent "revoked" record: an unrecognized key is indistinguishable from a never-known one, `docs/planning/decisions.md` D-23). | Security-relevant: MUST be shown in the UI (subject to the pre-pin-check scoping above), not only logged (UC-05). Text MUST be specific ("this device was unpaired"), distinct from `PIN_MISMATCH`'s "not trusted" wording. |
| 8 | `PROTOCOL_TIMEOUT` | Any deadline in §10 (E01-22) elapses without the required message: TLS handshake (10 s), `VersionHello` (5 s), or `MediaHello` on a media connection (5 s). The `PairRequest` 10 s deadline on a pairing-candidate connection is deliberately excluded here: exceeding it closes with `PAIRING_FAILED` (local reason `TIMEOUT`, row 5) instead. A `VersionHello`-deadline miss on a connection the verify callback has already accepted as a pairing candidate (§2, Pairing window) is the one case where a `PROTOCOL_TIMEOUT` close *does* burn a pairing attempt (`docs/planning/decisions.md` D-70): it is a candidate-slot connection closing before `PairAccepted`, exactly like any other case under §2's concurrency rule. Every other `PROTOCOL_TIMEOUT` — a TLS-handshake-deadline miss, or a `VersionHello`/`MediaHello` deadline miss on a connection that was never accepted as a pairing candidate — never burns an attempt, since no candidate slot was ever occupied. Heartbeat-based dead-connection detection (§7, E01-07: 45 s of silence on an established control session) is a separate, local transport-liveness event, not a close code: it triggers the phone's reconnect flow (E20-06) directly and MUST NOT be reported as `PROTOCOL_TIMEOUT`. | Generic connection-error message; MUST NOT be presented as a pin or version problem. If this occurs on a connection whose peer already passed the pin check (e.g. a recognized Mac that stalls before sending `VersionHello`), it MAY additionally be surfaced in the status area (E12-10) rather than suppressed as pre-pin-check network noise. |
| 9 | `LIMIT_EXCEEDED` | A peer or source address exceeds a connection-level cap in §10 (E01-22): more than 8 concurrent not-yet-Ready connections, or more than 2 from one source IP (excess sockets closed on accept, before the TLS handshake); a source IP with 10 or more failed handshakes within 60 s (refused for 60 s); a second concurrent pairing-candidate connection while one is already in flight (rejected in the verify callback without burning a pairing attempt, §2, E01-02); an older control session replaced by a newer Ready session for the same peer SPKI, closing the older one (E01-22); or a second media connection opened for a control session that already has one (E60-04). | Generic connection-error message; MUST NOT be presented as a pin or version problem. |

---

## Versioning and capability negotiation

*(E01-06 · PRD F-3.1 · AC-04 · invariant 5)*

This section defines `VersionHello`, the message each side of the control connection sends first,
and the required behavior on a version mismatch (fail closed, invariant 5) versus a capability
mismatch (feature-level degrade only, never a security downgrade).

### `VersionHello` fields

`VersionHello { major, minor, capabilities }` (`control.proto`, E01-12; `docs/planning/decisions.md`
D-63) carries exactly three fields:

- `major` — a `uint32` protocol major version. Two sides are version-compatible only if their
  `major` values are numerically equal; a difference in `major` is always fatal, regardless of
  `minor`. This version of the protocol sets `major = 1`. Because this field is a proto3 `uint32`,
  an unset field decodes as `0`; a peer whose `major` reads `0` (whether it never set the field, or
  deliberately set it to `0`) MUST be treated as a genuine major-version mismatch against this
  protocol's `major = 1` — proto3's default-value encoding MUST NOT be read as "no version stated"
  or otherwise given a pass. `major` is a separate concept from the TLS ALPN identifier `tandem/1`
  (§1, `docs/planning/decisions.md` D-19): ALPN is fixed at the TLS layer and never renegotiated
  within a session, while `major` is compared by the application after TLS completes, so a future
  major protocol revision can change one without necessarily changing the other. In this version both
  happen to read "1".
- `minor` — a `uint32` protocol minor version, additive within a `major`. Two sides with the same
  `major` but different `minor` values MUST still interoperate: a receiver on a lower `minor` MUST
  simply not receive whatever additive behavior a higher `minor` introduces, and a peer on a higher
  `minor` MUST remain compatible with a peer on any lower `minor` of the same `major` — a `minor` bump
  MUST NOT introduce a change serious enough to break an older peer of the same `major` (that always
  requires a `major` bump instead). This version of the protocol sets `minor = 0`.
- `capabilities` — a `uint64` bitmask of optional capability flags the sender supports. No bit is
  assigned a meaning in this version of the protocol: Phase 0 has no optional wire feature that needs
  negotiating. Every sender of this version MUST set `capabilities` to 0. A receiver MUST NOT act on,
  or gate any behavior on, any bit of `capabilities` in this version of the protocol — this holds even
  for a bit the receiver happens to recognize from a later draft, since no bit is normatively defined
  yet. A receiver MAY nonetheless record or expose the raw `capabilities` value it received (for
  example, alongside `lastSeen` in a peer's trust-store record, E12-14/E12-17) without that recording
  itself constituting "acting on" a bit. Once a future revision does assign bits, a receiver MUST
  always ignore any bit it does not recognize, never treating an unrecognized set bit as an error or
  a reason to close the connection. A future SPEC revision that assigns a capability bit documents it
  as an additive amendment to this section and MUST NOT repurpose or renumber a bit once shipped,
  using the same frozen-numbering discipline as close codes (§5) and channels (§4).

### Exchange rule

As §3 (`#framing-and-envelope`) already states: before both sides have exchanged `VersionHello` on
the control connection, the only legal payload on that connection is `VersionHello` itself; any other
payload arriving first MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`, closing with `MALFORMED_FRAME`.
Each side MUST send its own `VersionHello` as the first frame it transmits on `CONTROL` (`seq = 1`,
§3) without waiting for the peer's, then compares once its own has been sent and the peer's has been
received. No application frame — on any channel — MAY be sent by either side before both hellos have
been exchanged.

### Version mismatch

If the `major` fields the two sides exchange differ, both sides MUST close the connection with the
close code `VERSION_MISMATCH` (§5, `#errors-and-close-codes`, row 1) and show a visible error naming
the version mismatch specifically. A difference in `minor` alone, with matching `major`, is never a
`VERSION_MISMATCH` (see Exchange rule and `minor`, above). As §5 already states, this comparison
needs no separate wire signal: each side determines the mismatch locally by comparing the peer's
advertised `major` against its own, once both hellos have been received.

### Capability mismatch

- A receiver MUST NOT act on any `capabilities` bit in this version (see above); it MAY still record
  or expose the raw value it received.
- A receiver that does not recognize a `capabilities` bit the peer set MUST ignore it (see above).
- A capability bit MAY cause a receiver to disable an optional feature it does not support, but a
  capability bit MUST NOT ever be used to weaken, bypass, or downgrade the TLS profile (§1), the SPKI
  pin check (§1), the pairing protocol (§2), or media-ticket validation (§9): those are fixed
  protocol invariants, never negotiable per-connection features (invariant 5).
- Because no capability bit is assigned in this version, this section documents the negotiation rule
  now so the exchange mechanism — and the "never weakens security" constraint on it — exists before
  any capability bit actually needs it.

---

## Heartbeat

*(E01-07 · PRD F-3.4 · UC-04 · no invariant references)*

This section defines the control connection's wire-level liveness contract. The reconnect strategy
itself (address selection, backoff) is out of scope here (E20). Liveness is asymmetric: the Mac (the
control connection's server side, ADR-002) drives it by sending `Heartbeat`; the phone (the client
side) only answers (`docs/planning/decisions.md` D-10, D-46). `Heartbeat {}` (`control.proto`,
E01-12) carries no fields; a `Heartbeat` frame is an ordinary `CONTROL`-channel `Envelope` like any
other, subject to §3's `seq`/`ack` rules and, per §4, `CONTROL`'s own rate caps rather than
credit-based flow control.

### Interval and dead-peer threshold

- The Mac MUST send one `Heartbeat` on `CONTROL` after 15 s have elapsed since it last sent any frame
  on that connection — not only a `Heartbeat`; any frame it sends resets this 15 s idle timer.
- The Mac MUST treat the control connection as dead if it has not received any frame — `Heartbeat` or
  otherwise — from the phone within 45 s (three missed 15 s intervals) of the last frame it received
  from the phone.
- Symmetrically, the phone MUST treat the control connection as dead if it has not received any frame
  from the Mac within 45 s of the last frame it received (see Silence measurement, below).
- Declaring a connection dead by either side under this rule is a local, transport-liveness
  determination, not one of the §5 close codes: it MUST NOT be reported as `PROTOCOL_TIMEOUT` or any
  other close code (`docs/planning/decisions.md` D-58; §5's `PROTOCOL_TIMEOUT` row states this
  explicitly). On declaring the connection dead, the Mac MUST close its side of the control
  connection; the phone, on declaring the same, treats its session as ended and reconnects per E20-06
  regardless of whether the underlying socket has itself already errored.

### Reply obligation

- The phone MUST reply with exactly one `Heartbeat` to every `Heartbeat` it receives, within 1 s of
  receipt.
- The Mac MUST NOT reply to a `Heartbeat` it receives — there is no ping-pong loop. A `Heartbeat`
  arriving at the Mac only resets the Mac's own silence timer (see below); it never itself causes the
  Mac to send a `Heartbeat` in response.
- Per §4 and §10 (`docs/planning/decisions.md` D-60), the phone answers at most one `Heartbeat` per
  second; if `Heartbeat`s arrive faster than that, the phone MUST drop the excess silently — no
  reply, no error, no close.

### Mac-side receive cap on incoming Heartbeats

Every `Heartbeat` the Mac receives from the phone — whether it is a reply to a Mac-sent `Heartbeat`
or one the phone sent unsolicited (above) — MUST count toward the same 60-per-second-per-session
`CONTROL` receive cap that §4/§10 (`docs/planning/decisions.md` D-61) applies to non-`Heartbeat`
`CONTROL` frames; exceeding it closes the connection with `LIMIT_EXCEEDED`, exactly as for any other
`CONTROL` frame over that cap (`docs/planning/decisions.md` D-66). This closes the gap D-61's
original wording left open: D-61 bounds only *non*-`Heartbeat` `CONTROL` frames, and D-60 bounds only
the phone's own *reply* rate, so neither, on its own, bounds a compromised-but-authenticated phone
sending unsolicited `Heartbeat`s to the Mac far faster than the reply-triggering 15 s interval. The
phone's own receive-side cap on `CONTROL` frames from the Mac keeps the `Heartbeat` exclusion as
originally stated in D-61: Mac-sent `Heartbeat`s are inherently bounded by the Mac's own 15 s send
interval, so the phone has no equivalent gap to close.

### Unsolicited heartbeats and Doze

- The phone MAY send an unsolicited `Heartbeat` after 15 s of its own idle sending time while the
  device is interactive, to help keep the Mac's silence timer reset independent of feature traffic.
- The phone MUST NOT hold a wake lock or schedule an alarm merely to send an unsolicited `Heartbeat`
  while the device is in Doze. An incoming Mac-sent `Heartbeat` still reaches the phone in Doze
  because the foreground service holding the control connection runs with the unrestricted-battery
  exemption, which keeps network access available; this section states only the wire-visible
  obligation, and the platform mechanics are E20-15's concern.

### Silence measurement

- The phone MUST measure silence on a sleep-inclusive monotonic clock (`elapsedRealtime`, never
  wall-clock time, so it cannot be fooled by a clock change or miscounted during Doze) and MUST
  evaluate the "> 45 s since the last received frame" condition at least on its own liveness timer
  firing, on Doze exit, and on screen-on.
- Any frame received on the control connection, not only a `Heartbeat`, resets the silence timer on
  both sides: a channel actively carrying feature traffic (`NOTIFY`, `FILES`, etc.) is itself proof of
  liveness and counts the same as a `Heartbeat` for this purpose.

### Doze expectation (E20-12 overnight gate)

While the phone is in Doze with its foreground service running and unrestricted battery access
granted, the control connection either: (a) stays up — Mac-sent `Heartbeat`s reach the phone and its
replies reach the Mac, so 45 s of silence is never observed on either side — or (b), if the Mac has
already declared the connection dead and closed it, the phone MUST reconnect (E20-06) within 5 s of
its next Doze maintenance window or of the screen turning on, whichever occurs first.

---

## Discovery TXT record

*(E01-08 · PRD F-3.5 · UC-03, AC-05 · invariants 1, 3)*

This section defines the `_tandem._tcp` Bonjour/mDNS TXT record the Mac advertises so an already
paired phone can find a candidate address on the local network, without giving an unpaired observer
a stable identifier to track the Mac by. Discovery is a hint only: it never establishes trust and
never bypasses the handshake's SPKI pin check (§1).

### TXT record contents

The TXT record MUST contain exactly two keys, `v` and `id`, and no others:

- `v` MUST be the literal string `1`. A receiver that only recognizes `v=1` MUST ignore an
  advertisement carrying any other value without raising an exception. `v` identifies the shape of
  this discovery record itself and is independent of the `CONTROL`-channel `VersionHello.major`/
  `.minor` of §6, which governs the protocol spoken once a connection is actually made.
- `id` MUST be the 8-byte rotating identifier defined below, encoded as exactly 16 lowercase
  hexadecimal characters (no `0x` prefix, no separators).
- The TXT record MUST NOT contain the Mac's name, its SPKI fingerprint, or any other value that is
  stable across days or that identifies the specific Mac to an observer who is not already paired
  with it (AC-05).

### Rotating identifier

- `dayIndex = floor(unixSecondsUTC / 86400)`, an integer computed from the current UTC time — never
  the device's configured time zone — so the same instant yields the same `dayIndex` on the Mac and
  every phone regardless of each device's local time zone.
- HMAC input: `dayIndex` encoded as an unsigned 64-bit big-endian integer (8 bytes), consistent with
  this document's default big-endian convention (Conventions, above). This 8-byte value is the entire
  HMAC message.
- HMAC key: the issuing Mac's own SPKI fingerprint — SHA-256 over its DER-encoded
  SubjectPublicKeyInfo, the same 32-byte value the trust store persists and pins (`docs/PRD.md`
  "SPKI fingerprint", F-1.1) — MUST be used as the HMAC key, not the raw SPKI DER bytes. A phone's
  trust store holds only this fingerprint for each paired Mac, never the DER, so the fingerprint is
  the only value both sides can compute this identifier from.
- `id = ` the first 8 bytes of `HMAC-SHA256(key = macSpkiFingerprint, message = dayIndex as 8-byte
  big-endian)`.
- The Mac (advertiser) and each phone (matcher) compute this identically. A phone paired with more
  than one Mac computes one candidate `id` per stored Mac fingerprint and compares each against every
  advertisement it observes.
- A phone MUST compare `id` byte-for-byte (as lowercase hex) against each of its own computed
  candidates; an advertised `id` using uppercase hex, mixed case, or any other encoding that does not
  match a candidate exactly MUST be treated as non-matching and ignored — a receiver MUST NOT
  normalize case (or otherwise canonicalize) an advertised `id` before comparing it.
- The Mac MUST switch to advertising the new day's `id` within 1 s of 00:00:00 UTC, and MUST
  advertise the `id` for the current UTC day (never a stale one computed before sleep) within 1 s of
  waking; neither transition may cancel an already-open connection (E21-02 implements both cases on
  macOS).

### Skew tolerance

A receiver MUST compute and accept the `id` values for `dayIndex-1`, `dayIndex`, and `dayIndex+1`
(three candidate ids per paired Mac), to tolerate the UTC day boundary and modest clock skew between
devices. A receiver MUST NOT accept an `id` computed from any `dayIndex` outside that ±1 day window.

### Discovery is a hint only

- Discovery data — the fact that a `v=1`/`id` record was seen, or that its `id` matched a paired
  Mac's expected value — MUST NOT be used to establish trust, MUST NOT supply any key material, and
  MUST NOT bypass or shortcut the mTLS handshake's SPKI pin check (§1, invariants 1, 3). A match only
  produces a candidate network address for the phone's reconnect strategy (F-3.4, E20-06); the pin
  check on the resulting connection attempt is the only trust decision, and it runs exactly as it
  would for any other candidate address — including one that turns out to belong to an attacker
  replaying a paired Mac's currently valid `id` at a different address (`docs/threat-model.md` §4.16).
- A malformed or unmatched TXT record (a wrong-length or non-hexadecimal `id`, an unrecognized `v`,
  or extra or missing keys) MUST be ignored without raising an exception and MUST NOT affect
  discovery of other, well-formed advertisements.
- **Residual risk.** The rotating `id` is a function only of the Mac's SPKI fingerprint and the
  current `dayIndex`, both of which a former (now revoked) peer already knows from having been
  paired: revocation deletes the *phone's* record of trusting the Mac (§2, `docs/planning/decisions.md`
  D-23), but it cannot make the Mac's SPKI fingerprint itself unknown to a phone that saw it while
  paired. A revoked device can therefore still compute the Mac's current `id` and recognize its
  advertisement (and, per E21-02, the Bonjour service instance name, which is derived from the same
  `id`) indefinitely — this is not a trust bypass, since recognizing an advertisement only ever
  yields a candidate address for an ordinary connection attempt that the pin check (now lacking the
  revoked device's key) will fail, but it is a tracking/presence-disclosure residual worth recording
  here alongside the mDNS-hostname residual already noted in `docs/threat-model.md` §4.16.

---

## Media ticket

*(E01-09 · PRD F-3.3 · UC-22, AC-08 · invariants 1, 3, 6)*

The media connection is a second, full mTLS connection — the same identities and pins as the control
connection (§1, `docs/planning/decisions.md` D-19) — opened on demand for the high-bandwidth,
latency-sensitive mirroring stream (F-3.3). It never substitutes weaker authentication for the
ticket defined here: the `mediaTicket` only binds an already fully authenticated media connection to
the control session that requested it, so an unauthenticated party, or a party authenticated as a
different peer, cannot hijack it (AC-08).

### Issuance

- `MediaTicketGrant { ticket, expiresAt }` (`control.proto`, E01-12) is sent over the `CONTROL`
  channel by the issuing side (the Mac) in answer to a `RequestMediaTicket {}` (`media.proto`,
  E60-01), which the phone sends over `CONTROL` as the `Envelope` payload (field 8). `RequestMediaTicket`
  has no fields: the issuer takes the session and peer SPKI from the authenticated control connection,
  never from the message. Every `RequestMediaTicket` is answered with exactly one new
  `MediaTicketGrant` (see One outstanding ticket per control session, below).
- `ticket` MUST be exactly 32 bytes (256 bits), generated by a CSPRNG for every issuance. A receiver
  MUST reject a `MediaHello` (below) whose `ticket` field is any other length before comparing it to
  anything.
- `expiresAt` denotes the instant, milliseconds since the Unix epoch (UTC), 30 s after the moment of
  issuance. The issuer MUST record the 30 s deadline internally at issuance and MUST expire the
  ticket exactly 30 s after issuance regardless of what a receiver does with the wire-carried
  `expiresAt` value — the issuer is also the validator (the same Mac process), so it never trusts a
  wire-carried expiry against itself; the field exists only so the requesting side can avoid a doomed
  dial once its own copy of the deadline has passed.
- The issuer MUST record, alongside the ticket, the issuing control session's authenticated peer SPKI
  so validation can later check both the ticket value and the presenting peer's identity.

### Consumption and single use

- `MediaHello { ticket }` (`media.proto`, E60-01) MUST be the first frame on the media connection (§3
  already states this). The media connection carries no `Envelope` and has no channel: the body of
  its first length-prefixed frame (§3) is the serialized `MediaHello` message itself.
  Because a pinned peer's role on a newly accepted connection is otherwise ambiguous, the first frame
  itself is what distinguishes the two: a pinned-peer connection whose first frame is `MediaHello` is
  a media connection; one whose first frame is `VersionHello` (§6) is a control connection — both are
  accepted on the same single listener (`docs/planning/decisions.md` D-03).
- A `MediaHello` arriving on a **pairing-candidate** connection (§2 — a connection still inside the
  pairing window, not yet an ordinary authenticated peer) MUST be rejected as `UNKNOWN_PAYLOAD_TYPE`,
  closing with `MALFORMED_FRAME` (§3) — the same treatment as any other payload illegal for a
  connection's current state — without ever consulting the ticket table: pairing candidates are never
  eligible to open a media connection (`docs/planning/decisions.md` D-25).
- On an ordinary (already fully authenticated, non-pairing-candidate) connection, the validating side
  MUST validate a presented `ticket` in exactly this order, stopping at the first matching case
  (`docs/planning/decisions.md` D-65):

  0. **Absent or malformed.** `ticket` is absent, or present but not exactly 32 bytes → reject
     `MISSING`, before comparing it against anything held.
  1. **No match.** Compare `ticket`, in constant time, against every ticket this validator currently
     holds (§ Issuance, and Retention below — this includes tickets already consumed, expired but not
     yet purged, or bound to a since-ended session; nothing is excluded from this comparison set). If
     it matches none of them → reject `REUSED`.
  2. **Peer mismatch.** It matches a held ticket, but the connection presenting it is authenticated as
     a different peer than the SPKI the ticket was issued to → reject `OTHER_SESSION`, and — because a
     ticket presented by the wrong peer must be assumed to have leaked to that peer — permanently
     invalidate the matched ticket as a side effect, even though this presentation itself is rejected
     (see Invalidate-on-mismatch, below).
  3. **Session ended.** The peer matches, but the ticket's issuing control session has since ended →
     reject `OTHER_SESSION`.
  4. **Expired.** The session is still the issuing one, but 30 s have elapsed since issuance → reject
     `EXPIRED`.
  5. **Already consumed.** Not expired, but the ticket was already marked consumed by an earlier
     successful validation → reject `REUSED`.

  A presentation matching none of cases 0–5 is valid: the validating side MUST mark it consumed and
  bind the media connection to the ticket's issuing control session before accepting any further
  frame, in particular before accepting any media data.
- **Invalidate-on-mismatch.** Case 2 above (peer mismatch) is the only rejection case that
  additionally burns the ticket: once a ticket has been observed presented by a peer other than the
  one it was issued to, it MUST NOT be usable by *any* peer afterward, including the correct one — the
  mismatched presentation is itself evidence the ticket value is no longer secret. Cases 0 and 1 (an
  absent, malformed, or entirely unrecognized `ticket`) never burn anything, by construction: neither
  case has a held ticket record to act on, so a guess can never invalidate the real ticket it happened
  not to match. Cases 3, 4 and 5 need no additional invalidation step beyond what already applies: a
  ticket rejected for one of those reasons is already, respectively, unbindable (its session is gone),
  inherently one-shot-expired, or already consumed.
- Every ticket comparison — the constant-time search of case 1, and any other bytewise check —
  MUST use a constant-time comparison (invariant 6).

### Conformance

`protocol/vectors/media-encoding.json` (E60-01; E15-01, E15-02) includes: `RequestMediaTicket`,
`MediaTicketGrant` (32-byte ticket, `expiresAt` 30 s after issuance) and `MediaHello` each
round-tripping to their golden bytes on both codecs; and a `MediaHello` with no `ticket` field, with
a 31-byte `ticket` and with a 33-byte `ticket`, each rejected by both parsers as `TICKET_REJECTED`
(local reason `MISSING`, case 0) from the decoded message alone, before any further frame is read.

### Rejection

Every case in the ordered algorithm above closes the media connection with the close code
`TICKET_REJECTED` (§5, `#errors-and-close-codes`, row 6), using the local reason the matching case
names (`MISSING`, `REUSED`, `OTHER_SESSION`, or `EXPIRED`), and MUST NOT affect, close, or otherwise
degrade the control session that issued the ticket — the two connections are independent once
established.

The first frame on a media connection MUST arrive within 5 s of TLS completion (§10,
`#timeouts-connection-limits-and-resource-caps`, E01-22); exceeding that deadline closes the
connection with `PROTOCOL_TIMEOUT` (§5) rather than `TICKET_REJECTED`, since no `MediaHello` — and
therefore no ticket — was ever presented to reject.

### Handling requirements

- A ticket MUST NOT be logged, in full or in part, on either side, at any log level, in a debug or a
  release build (`docs/planning/decisions.md` D-25, invariant 7).
- A ticket MUST NOT be persisted to disk. **Retention.** A ticket record is retained in memory —
  marked consumed, session-ended, or invalidated-by-mismatch as each event occurs, rather than removed
  from the table — until exactly 30 s after its issuance, at which point the issuer MUST purge it.
  This is a deliberate departure from discarding a ticket the instant its session ends or it is
  consumed: retaining the (marked) record until every ticket's same absolute 30 s deadline is what
  lets the ordered algorithm above distinguish `REUSED` from `OTHER_SESSION` from `EXPIRED` precisely,
  instead of every one of those cases collapsing to "no match" (case 1) once the record is gone
  (`docs/planning/decisions.md` D-65). A ticket is never valid across a restart of either process and
  never valid for any control session other than the one that requested it — not even a later session
  between the same two peers.
- **One outstanding ticket per control session.** A control session has at most one currently valid
  (unconsumed, unexpired, not-yet-superseded) ticket outstanding at a time. If that session requests a
  new ticket while a previously issued one is still outstanding, the issuer MUST supersede the old one
  — treating it exactly as if consumed, so any later presentation of it is rejected `REUSED` — at the
  moment it issues the new one.
- **The requesting side's own deadline.** The requesting side (the phone, dialing the media
  connection) MUST compute its own deadline for a ticket as the instant it received the
  `MediaTicketGrant` plus 30 s, measured on its own monotonic clock — not by trusting the wire-carried
  `expiresAt` value, which reflects only the issuer's clock and does not account for delivery delay or
  clock skew between the two devices. `expiresAt` remains useful only as a record of the issuer's own
  30 s deadline (§ Issuance, above); the requesting side's decision to still attempt the dial MUST use
  its own measurement instead.

---

## Timeouts, connection limits and resource caps

*(E01-22 · PRD F-3.1, F-3.2, F-3.3 · AC-04, AC-13, AC-19 · invariants 1, 3, 5)*

This section collects every timeout, concurrency cap, and size/rate limit in the protocol into one
place, so both platforms enforce identical numbers and so the mitm-lab/pcap-audit test suites (E15-20,
E71-08) can attack them directly. Three rules govern every row below:

- Over-cap input MUST be rejected before any allocation or side effect it would otherwise cause — §3
  already states this for the 1 MiB frame-length prefix; every other cap in this section follows the
  same rule.
- No limit in this section ever relaxes the TLS profile (§1), the SPKI pin check (§1), the pairing
  protocol (§2), or media-ticket validation (§9): these are resource/DoS bounds only, never a way to
  skip or weaken a trust decision.
- A source IP address is used only as a throttling key anywhere in this section; it is never a trust
  input (invariant 3) — passing a per-IP cap grants no trust, and failing one never revokes any.

### Pre-authentication deadlines and connection caps

Enforced by the Mac's listener (E12-18) unless noted otherwise:

| Item | Value | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| TLS handshake deadline | 10 s from TCP accept (Mac); 10 s from `connect()` (phone, dialing) | `PROTOCOL_TIMEOUT` (§5) | E12-18 (Mac), E12-08 (phone) |
| `VersionHello` deadline | 5 s after TLS completion, both sides | `PROTOCOL_TIMEOUT` (§5) | E12-07 (Mac), E12-15 (Android) |
| `PairRequest` deadline | 10 s after both `VersionHello`s are exchanged on a pairing-candidate connection (§2) | `PAIRING_FAILED`, local reason `TIMEOUT` — not `PROTOCOL_TIMEOUT` (§5); burns one pairing attempt like any other failed attempt | E14-02 |
| `MediaHello` deadline | 5 s after TLS completion on a media connection (§9) | `PROTOCOL_TIMEOUT` (§5) | E60-03 |
| Concurrent not-yet-`Ready` connections | ≤ 8 total | excess sockets closed on accept, before the TLS handshake starts — not a close code, since no protocol session ever begins | E12-18 |
| Concurrent not-yet-`Ready` connections, per source IP | ≤ 2 | same as above | E12-18 |
| Failed-handshake throttle | a source IP with ≥ 10 failed handshakes within a rolling 60 s window is refused for 60 s; peers on other addresses are unaffected | new connection attempts from that IP refused at accept, not a close code | E12-18 |
| Concurrent pairing-candidate connections | ≤ 1 | a second unknown client certificate while one is in flight is rejected in the verify callback (§1) without burning a pairing attempt; if this is instead observed as a connection close, it is `LIMIT_EXCEEDED` (§5 row 9) | E12-02, E14-02 |

A **failed handshake**, for the throttle above, is any of: a TLS handshake that does not complete
within its 10 s deadline (the row above) — this includes an idle TCP connection that never sends a
`ClientHello` at all, which counts once its 10 s deadline elapses, not merely once actively rejected;
a completed handshake rejected by the verify callback (§1) for any reason (pin mismatch, a
non-conforming leaf key, or a pairing-candidate rejected only because the candidate slot was already
occupied, `LIMIT_EXCEEDED`); or a TCP connection that closes or resets before a `ClientHello` is ever
received. This throttle is a per-source-IP counter and is therefore weak against an attacker who
rotates across several source addresses on the same network (e.g. several IPv6 privacy addresses) —
an accepted residual noted alongside the related pre-auth-budget residual in `docs/threat-model.md`
§4.1.

### Pairing-specific deadlines (§2)

| Item | Value | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| Pairing window duration / attempt budget | 120 s open, ≤ 3 attempts (§2, Pairing window) | past 120 s: window closes, in-flight candidate (if any) closed `PAIRING_FAILED` local reason `EXPIRED`; after the 3rd failed attempt: window closes (local state `attemptsExhausted`) and a 4th candidate is refused in the verify callback (§1), never reaching `PAIRING_FAILED` | E14-02 |
| Per-address pairing dial timeout | 3 s per QR address (§2, Dialing the QR addresses; `docs/planning/decisions.md` D-68) | dial advances to the next QR address; `Failed(AllAddressesUnreachable)` if every address times out | E14-05 |
| Phone-side wait for `PairAccepted`/`PairRejected` after sending `PairRequest` | 120 s (§2, Frame order, step 6) | phone treats the attempt as `Failed(Timeout)` (or `Failed(ConnectionLost)` if the connection ends first) | E14-05 |
| Phone-side "Codes match" confirmation wait | 120 s after receiving `PairAccepted` (§2, Mutual confirmation) | phone sends `Revoke {}` over the now-trusted session and commits nothing | E14-05 |

### Post-authentication caps

| Item | Value | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| Control sessions per peer SPKI | 1 (a newer `Ready` session for the same peer replaces — closes — the older one) | older session closed `LIMIT_EXCEEDED` (§5 row 9) | E12-19 |
| Media connections per control session | ≤ 1 | second media connection for a session that already has one closes `LIMIT_EXCEEDED` (§5 row 9) | E60-04 |
| Frame size | ≤ 1 MiB (§3) | `MALFORMED_FRAME` | E11-02, E11-04 |
| Per-channel credit cap | ≤ 64 credits, receiver's own choice per channel (§4) | `CREDIT_VIOLATION` | E11-07, E11-08, E11-13, E11-14 |
| Media access unit | ≤ 8 fragments, ≤ 8 MiB reassembled (§12, TBD in E61-01) | `MALFORMED_FRAME`, local reason `FRAGMENT_VIOLATION` | E61-01 |
| Media ticket validity | 30 s from issuance (§9, Issuance) | `TICKET_REJECTED`, local reason `EXPIRED` | E01-09, E60-08 |

### `CONTROL` channel caps

`CONTROL` is exempt from the per-channel credit cap above — control/heartbeat traffic MUST never be
backpressured (§4) — and instead has its own fixed-rate caps
(`docs/planning/decisions.md` D-60, D-61, D-66):

| Item | Value | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| `Heartbeat` send interval (Mac, idle trigger) | 15 s since the Mac last sent any frame (§7, Interval and dead-peer threshold) | Mac sends `Heartbeat` | E20-05 |
| Dead-peer threshold (both sides) | 45 s of silence since the last received frame (§7) | local transport-liveness event, not a close code — MUST NOT be reported as `PROTOCOL_TIMEOUT` (§5 row 8, `docs/planning/decisions.md` D-58) | E20-05 (Mac), E20-15 (phone) |
| `Heartbeat` reply deadline (phone) | 1 s of receiving a `Heartbeat` (§7, Reply obligation) | phone sends its reply | E20-15 |
| `Heartbeat` replies (phone → Mac) | ≤ 1 per second | excess dropped silently: no reply, no error, no close | E20-15 |
| Non-`Heartbeat` `CONTROL` frames received, either side | ≤ 60 per second per session | `LIMIT_EXCEEDED` | E20-05 (Mac), E20-15 (phone) |
| All `CONTROL` frames received at the Mac, including every `Heartbeat` (reply or unsolicited) | counted toward the same 60/s cap above | `LIMIT_EXCEEDED` | E20-05, E20-20 |

### `Ring`/`RingStop` cooldown

`docs/planning/decisions.md` D-62:

| Item | Value | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| `Ring` while already ringing | idempotent: a second `Ring` is a no-op, not a second alarm | no error | E23-06 |
| Alarm starts | ≤ 2 per rolling 10 s window, regardless of how many `Ring` frames arrive in that window | excess `Ring` frames are accepted but do not start a new alarm; no error, no close | E23-06, E23-08 |

### Feature caps

These numbers are recorded here as the single source of truth (`docs/planning/decisions.md` D-21,
D-44); the owning feature's own SPEC section, once written, restates the same number rather than
redefining it.

| Feature | Cap | Violation behavior | Implementing issue(s) |
|---|---|---|---|
| Notifications: title | ≤ 256 characters | rejected/truncated | E30-01 |
| Notifications: text/body | ≤ 4096 characters | rejected/truncated | E30-01 |
| Notifications: `MessagingStyle` sender names | ≤ 25 names, ≤ 64 characters each | rejected/truncated | E30-06 |
| Notifications: icon | PNG ≤ 64 KiB, ≤ 256×256 px | rejected | E30-07 |
| Notifications: Mac-retained delivered notifications | ≤ 50 | oldest dropped | E30-01 |
| Notifications: `NotificationAction.replyText` | ≤ 4096 characters | rejected/truncated | E30-09 |
| Files: raw name | ≤ 1024 UTF-8 bytes | rejected | E40-01 |
| Files: mime type | ≤ 255 bytes | rejected | E40-01 |
| Files: size | ≤ 64 GiB | `TOO_LARGE` | E40-01 |
| Files: unanswered offers | ≤ 4 | `BUSY` | E40-07 |
| Files: active transfers, per direction | ≤ 2 | `BUSY` | E40-18 |
| Files: auto-accept | only offers ≤ 1 GiB; opt-in setting, off by default | offers over the cap always require a manual accept regardless of the setting | E40-07, E40-18 |
| Photos: outstanding `ThumbRequest`s per peer | ≤ 8 | `BUSY` | E41-04 |
| Photos: outstanding `PhotoPage` per peer | ≤ 1 | `BUSY` | E41-01 |
| SMS: `SmsSyncRequest` in flight | ≤ 1 (a new one supersedes the old) | — | E50-01 |
| SMS: `SendSmsRequest` body | ≤ 1600 characters | `TOO_LONG` | E50-04 |
| SMS: sends | ≤ 10 per rolling 60 s | `RATE_LIMITED` | E50-13 |
| Calls: `PlaceCallRequest.address` | MUST match `^\+?[0-9]{3,20}$` after removing spaces and dashes (no `*`, `#`, `,`, `;`) | `INVALID_NUMBER` | E52-01 |
| Calls: request rate | ≤ 1 per 5 s | `RATE_LIMITED` | E52-05 |
| Input: `InputEvent` rate | ≤ 120/s sustained, burst ≤ 240; excess dropped and counted | dropped, no close | E62-01 |
| Input: `SetText`/`TextEdit.insert` | ≤ 4096 characters | rejected | E62-01 |
| Input: `Swipe.durationMs` | 1..5000 | rejected | E62-01 |
| Input: coordinates | within the reported window bounds | dropped, never clamped | E62-06 |
| Clipboard | ≤ 1 MiB | no frame sent; sender-side "too large" toast | E31-06 |

### Pairing-window DoS trade-off

An attacker within radio range of an open pairing window can burn all 3 attempts, denying that
specific window to the legitimate phone. This is visible to the owner on the Mac (the failed-attempt
count, or a declined/failed pairing dialog) and is recovered by regenerating the QR, which opens a
fresh window with a fresh secret and resets the attempt budget (E14-11). This is an accepted,
annoyance-level denial of service (`docs/threat-model.md` §4.3) — it never grants the attacker trust,
since burning attempts never bypasses the proof check or the owner's Mac-side confirmation (§2).

---

## Untrusted peer strings (display sanitization)

*(E01-23 · PRD F-2.1, F-5.1, F-7.1, F-8.1, F-8.4 · AC-14 · no invariant references)*

Every string one peer supplies that the other peer displays is untrusted input, regardless of which
channel carried it or whether the sender is already an authenticated, paired identity — a
compromised-but-still-pinned peer can supply a hostile string just as easily as an unpaired one. This
section defines one sanitization rule, applied identically to every such surface.

### Surfaces this rule applies to

Each surface below is tagged with its length-cap category — `name` (64 characters), `title` (256
characters), or `body` (4096 characters) — unless §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22) states a different cap for that specific
field, in which case that cap applies instead of the default for its category:

- Pairing (§2): `PairRequest.deviceInfo.displayName`, `.model` (`name`); the QR `n` field (`name`;
  §2's 64-UTF-8-byte wire cap applies before decoding, this section's `name` cap applies again to what
  is actually rendered).
- Trust store: a peer's `displayName` recorded at pairing time (`name`).
- Notifications (§ TBD, E30): app name (`name`), title (`title`, capped at 256 per §10), body/text
  (`body`, capped at 4096 per §10), `MessagingStyle` sender names (`name` each, ≤ 25 of them per §10).
- Files (§ TBD, E40): file names shown in accept/progress prompts, after E40-02's separate
  path-safety filename rule has already run (`name`; the on-disk filename rule itself is out of scope
  here).
- SMS (§ 14, E50): sender/recipient addresses (`name`); message snippets and *displayed incoming*
  bodies (`body`, capped at 1600 characters — §10's SMS cap is defined there as an outgoing
  `SendSmsRequest` *send* limit, `TOO_LONG`; this section applies that same 1600 number to an incoming
  body as the display cap, since no larger displayed-body cap has been separately decided).
- Contacts (§ TBD, E51): contact display names (`name`).
- Calls (§ TBD, E52): caller display names and SIM display names (`name`).

### Sanitization order

Applied, in this exact order, to every surface above before the string is ever rendered:

1. Decode the raw bytes as UTF-8; any byte sequence that is not valid UTF-8 MUST be decoded with each
   invalid sequence replaced by U+FFFD (REPLACEMENT CHARACTER) — never silently dropped and never left
   as raw bytes.
2. Normalize the decoded text to Unicode Normalization Form C (NFC).
3. Remove every bidirectional-control code point: U+202A–U+202E, U+2066–U+2069, U+200E, U+200F, and
   U+061C.
4. Remove every C0 and C1 control code point, except U+000A (line feed): U+000A MUST be preserved in a
   multi-line `body` field, and MUST itself be removed in a single-line `name` or `title` field.
5. In a single-line field (`name` or `title`), additionally remove every zero-width code point —
   U+200B–U+200D, U+2060, U+FEFF — and collapse any run of whitespace to a single U+0020.
6. Re-apply Unicode Normalization Form C (NFC) after step 5: removing a code point between a base
   character and a combining mark in steps 3–5 can leave a result that is no longer normalized, so NFC
   MUST be re-checked here even though step 2 already applied it once.
7. Truncate the result to the surface's length cap, where the cap counts Unicode scalar values (code
   points after normalization, not UTF-8/UTF-16 code units), breaking only on a grapheme-cluster
   boundary (never mid-cluster or mid-code-point). If truncation occurred, append a single U+2026
   (HORIZONTAL ELLIPSIS); the appended ellipsis itself does not count against the cap, so the rendered
   result of a truncated string is at most the cap plus one scalar value.

### Rendering rule

Every sanitized string MUST be rendered as plain text only: no Markdown, no rich/attributed-string
markup interpretation, and no OS data-detector pass that would turn any part of the text into a
tappable link, phone number, or other action. A peer-supplied string is data, never a UI affordance.

### Trust scope

No trust decision anywhere in this protocol is ever based on a peer-supplied name, title, or body
string: pairing's trust decision relies exclusively on the confirmation code (§2,
`#pairing`), derived from cryptographic material, never on the displayed device name or model.
Homoglyph/confusable-character detection is explicitly out of scope for this same reason — even a
perfectly convincing confusable name changes nothing about which key the owner is trusting, so
detecting it would not close any actual gap (residual risk recorded in `docs/threat-model.md` and in
`docs/planning/decisions.md` D-22).

### Conformance

`protocol/vectors/` (E01-24) is the authoritative vector suite for this rule on both platforms: each
vector gives an input string, a `kind` (`name`, `title`, or `body`), and the expected sanitized output.
E14-21 (Android) and E14-22 (macOS) implement a shared sanitizer validated against these vectors.

---

## STATUS channel

*(E23-01 · PRD F-4.3, F-4.4 · UC-05, UC-06 · no invariant references)*

The STATUS channel carries two message types: `DeviceStatus` (the phone sends this to report battery,
network, and signal state) and `Ring`/`RingStop` (the Mac sends `Ring` to make the phone ring; either
side sends `RingStop` to stop it). The semantics below govern publish rate and direction:

### DeviceStatus publish rule

- **Direction:** Phone → Mac only. The phone publishes on every change of `battery_level`, 
  `is_charging`, `network_type`, or `signal_level`.
- **Throttle:** At most one `DeviceStatus` per 60 seconds. If a change occurs within 60 s of the
  previous send, the new values are coalesced (the latest values overwrite earlier ones in that window)
  and sent exactly once at 60 s after the last send. If no change occurs for 60+ seconds, nothing is
  sent until the next actual change.
- **Session Ready:** Immediately upon the session reaching Ready, the phone sends the current 
  `DeviceStatus` once, applying the same publish rule: if a change occurred within the last 60 s of
  session negotiation, the latest values are sent; otherwise, the current values at Ready time are
  sent.

### Ring/RingStop flow

- **Ring (Mac → Phone):** The Mac sends `Ring` to make the phone play an alarm at max volume,
  overriding Do Not Disturb, until dismissed. See §10 (`#timeouts-connection-limits-and-resource-caps`,
  E01-22) for the cooldown cap: the alarm starts at most twice per rolling 10 s regardless of how many
  `Ring` frames arrive.
- **RingStop (either direction):** Either side may send `RingStop` to stop the ringing alarm. The
  `origin` field records which side initiated the stop (mac or phone), answering the question "did the
  phone dismiss this, or did the Mac cancel it?" on the receiving side, so each side's UI can reflect
  the appropriate cause.

### Conformance

`protocol/vectors/` (E01-16) includes encode/decode and round-trip vectors for a full `DeviceStatus`
and a `Ring`/`RingStop` pair; both Kotlin and Swift codecs produce byte-identical encodings for these
vectors (E15-01, E15-02).

---

## NOTIFY channel

*(E30-01 · PRD F-5.1, F-5.2, F-5.3, F-5.4 · UC-08, UC-09, UC-10, AC-14, AC-19 · invariant 7)*

The NOTIFY channel (`Channel.NOTIFY`, §4) mirrors Android notifications to the Mac and forwards
actions/dismissals back. It carries five message types, each sent directly as the Envelope
payload (no wrapper message): `NotificationPosted` and `IconData` (phone → Mac),
`NotificationAction` (Mac → phone), `NotificationActionResult` (phone → Mac), and
`NotificationDismiss` (either direction).

### NotificationPosted and default filter

The phone sends `NotificationPosted` when a notification is posted or updated; a second
`NotificationPosted` with the same `key` updates the Mac's presentation of that notification
rather than stacking a new one (E30-02). Before any notification reaches this channel it passes
the default filter (E30-03), which drops: (1) Tandem's own package; (2) packages `android` and
`com.android.systemui`; (3) any notification carrying `FLAG_FOREGROUND_SERVICE`; (4) group-summary
notifications (children are still forwarded); (5) `MediaStyle` notifications (media control is
F-10.1, a separate feature). This rule set is authoritative here; its implementation is checked in
as `android/feature/notifications/SYSTEM_NOISE.md` (E30-03). A per-app allow/deny setting
(E30-04) overrides this default filter and is phone-side only (`docs/planning/decisions.md` D-04,
D-50) — the Mac shows no per-app list in v1.

### IconData

`IconData` carries a source app's icon, keyed by `package_name` + `version_code` (not per
notification): the Mac caches it and reuses it for every `NotificationPosted` from that app
version that sets `has_icon = true` (E30-05, E30-06). A missing or over-cap icon (§10) falls back
to a generic placeholder rather than blocking the notification's presentation.

### VISIBILITY_SECRET handling

A notification marked `VISIBILITY_SECRET` is forwarded in redacted form unless the user has
opted in to "Show content of secret notifications on Mac" in phone settings (default off,
E30-11): `title` = the app name, `text` = `""`, `messaging_style_senders` = `[]`,
`visibility` = `VISIBILITY_SECRET`. The phone never sends the real content in the non-opted-in
case — this is a sender-side redaction, not something the Mac must apply itself.

### NotificationAction and NotificationActionResult

The Mac sends `NotificationAction` when the user taps an action or submits a reply on a mirrored
notification, identifying the source action by `key` + `action_index` and carrying `reply_text`
for a RemoteInput-capable action (E30-08, E30-09). The phone answers every received
`NotificationAction` with exactly one `NotificationActionResult` for the same `key`: `OK` once the
action's `PendingIntent` is sent; `GONE` if `key` no longer refers to a live notification (already
dismissed or expired — UC-09 alternate); `FAILED` if sending the `PendingIntent` throws (e.g.
`CanceledException`), including a `reply_text` over the §10 cap, which is answered `FAILED`
without attempting to send.

### NotificationDismiss

Dismissing a notification on either side sends `NotificationDismiss{key, origin}`: `origin` records
which side dismissed it (`ORIGIN_ANDROID` or `ORIGIN_MACOS`) so the receiving side can apply the
removal locally (`NotificationListenerService.cancelNotification` on Android, E30-10;
`NotificationPresenter.removeDelivered` on macOS, E30-18) without re-forwarding a dismissal it only
just applied itself — this prevents an echo loop between the two sides.

### Disconnected-phone notification buffer

While the phone's session is not Connected, `NotificationPosted` (and its matching
`NotificationDismiss`) are held in memory only, never persisted to disk
(`docs/planning/decisions.md` D-45): at most 50 entries; an entry older than 60 s is evicted before
flush; when the buffer is full, the oldest entry is dropped first to make room for a new one. A
`NotificationDismiss` for a still-buffered key removes that entry from the buffer instead of being
sent — neither the post nor the dismiss reaches the Mac in that case (UC-08 alternate). On
reconnect, buffered posts are flushed oldest-first and the buffer is empty afterward. This policy
is implemented by E30-16.

### Feature caps and sanitization

§10 (`#timeouts-connection-limits-and-resource-caps`, E01-22) is the single source of truth for
every numeric cap in this section; restated here for convenience: `title` ≤ 256 characters, `text`
≤ 4096 characters, `messaging_style_senders` ≤ 25 entries of ≤ 64 characters each, `IconData`
PNG ≤ 64 KiB and ≤ 256×256 px, `NotificationAction.reply_text` ≤ 4096 characters. Every string
field on this channel — `title`, `text`, each `messaging_style_senders` entry, and the app name a
receiver looks up for `package_name` — is untrusted peer input and MUST pass
§11 (`#untrusted-peer-strings-display-sanitization`, E01-23) before being rendered, exactly like
every other surface in that section. None of these fields, nor any notification body/text they
carry, is ever written to a log in a release build (invariant 7): the same
`DisplayStringSanitizer`/release-log rules that keep secrets out of logs elsewhere in this
protocol apply to this channel without exception.

### Conformance

`protocol/vectors/` (E15-01, E15-02) includes frame-level encode/decode round-trip vectors for
this channel: a `NotificationPosted` with a `MessagingStyle` post carrying 3 senders, a
`NotificationAction` with a reply, a `NotificationDismiss` with `origin = ORIGIN_MACOS`, an
`IconData`, and a `NotificationActionResult` with `status = STATUS_GONE`. Both the Kotlin and
Swift codecs produce byte-identical encodings for these vectors.

---

## CLIPBOARD channel

*(E31-01 · PRD F-6.1, F-6.2, F-6.3 · UC-12, UC-13 · invariant 7)*

The CLIPBOARD channel (`Channel.CLIPBOARD`, §4) synchronizes plain-text clipboard/pasteboard
content between the two sides. It carries exactly one message type, sent directly as the Envelope
payload (no wrapper message): `ClipboardText { origin_tag, content_hash, text, sensitive }`
(`protocol/proto/tandem/v1/clipboard.proto`). Either side may send it: the Mac on an
`NSPasteboard.changeCount` poll (F-6.1), the phone from a share-sheet target, Quick Settings tile,
`PROCESS_TEXT` selection, or foreground-app read (F-6.2). A concealed or transient source item
(`org.nspasteboard.ConcealedType`/`TransientType`/`AutoGeneratedType`) is filtered out on the
sending side and never reaches this message type at all (E31-03).

### Size limit

`text` MUST be at most 1,048,576 bytes (1 MiB, 2^20) of UTF-8, restated from §10
(`#timeouts-connection-limits-and-resource-caps`, E01-22) "Feature caps" as the single source of
truth for the number. A sender MUST reject an over-cap item rather than truncating it: no
`ClipboardText` frame is sent for it at all, and the sending side's UI shows a "too large to send"
hint instead (E31-04, E31-06, E31-11, E31-12). Truncating an over-cap clip would silently corrupt
its content on the receiving side, which is worse than not sending it.

### `content_hash` and echo-loop prevention

`content_hash` is the SHA-256 digest (32 raw bytes) of `text`'s UTF-8 bytes, computed the same way
this protocol computes every other content fingerprint (`SpkiFingerprint`, §1; `FileOffer.sha256`,
PRD F-7.1): `content_hash = SHA-256(UTF-8(text))`.

`origin_tag` identifies which side last wrote this content — the literal string `"macos"` or
`"android"` — and, together with `content_hash`, is how each side avoids re-broadcasting content it
only just received (an echo loop: Mac → phone → Mac → ... forever). Before writing a received
`ClipboardText` to its local pasteboard/clipboard, a side records the pair `(origin_tag,
content_hash)` alongside the local change-detection cursor the write itself causes (the
`NSPasteboard.changeCount` it produces on macOS, or the equivalent on Android) — E31-08 (Android),
E31-14 (macOS). When that side's own change poller next detects a local clipboard change, it first
computes that new content's `content_hash` and compares it to the most recently recorded pair: if
the hash matches, the change is recognized as the side's own just-applied write echoing back
through the OS pasteboard API, and it is not sent. The recorded pair is cleared as soon as a
genuinely different local change (one whose hash does not match) is sent, so a later, unrelated
recurrence of the same content is sent normally rather than being suppressed forever.

### `sensitive` flag

`sensitive` is `true` when the sender considers the content's source sensitive — for example, an
Android password manager that set `EXTRA_IS_SENSITIVE` on the source text (PRD F-6.2, F-6.3). A
receiver writes a `sensitive` clip to its local pasteboard/clipboard with the
`org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` markers (E31-13) so that
clipboard-history managers, and this protocol's own change poller on that side, both skip it —
the same concealed-type filter (above) that stops such content from being sent back out. `text` is
untrusted, potentially secret content regardless of `sensitive`'s value: per invariant 7
(`docs/planning/decisions.md`), it MUST NOT be written to a log in a release build, and the
`sensitive` flag does not relax that rule for a `false`-flagged clip — it only changes how the
*receiving* side stores the content locally, never whether it may be logged.

### Conformance

`protocol/vectors/clipboard-encoding.json` (E15-01, E15-02) includes a `ClipboardText` with
`sensitive = true` that round-trips byte-identically through both the Kotlin and Swift codecs, a
`text` of exactly 1,048,576 bytes (accepted), and a `text` of 1,048,577 bytes — one byte over the
cap above — rejected by both codecs rather than truncated.

---

## FILES channel

*(E40-01 · PRD F-7.1 · UC-14, UC-15, UC-16, AC-19 · invariants — none)*

The FILES channel (`Channel.FILES`, §4) transfers whole files between the two sides: offer,
accept-or-reject, chunked transmission, completion, cancellation, and resume of an interrupted
transfer. It carries seven message types, each sent directly as the Envelope payload (no wrapper
message): `FileOffer{id, name, size, mime, sha256}`, `FileAccept{id}`,
`FileReject{id, reason}`, `FileChunk{id, seq, offset, data}`, `FileComplete{id}`,
`FileCancel{id, reason}`, and `FileResumeRequest{id, from_offset}`
(`protocol/proto/tandem/v1/files.proto`). `id` is sender-assigned per transfer and threaded through
every message referring back to it; it is never reused for a different transfer.

`reason` (on `FileReject` and `FileCancel`) is the shared `TransferReason` enum:
`DECLINED`, `TIMEOUT`, `INSUFFICIENT_SPACE`, `INVALID_NAME`, `HASH_MISMATCH`,
`PROTOCOL_VIOLATION`, `USER_CANCELLED`, `UNKNOWN_TRANSFER`, `SOURCE_UNAVAILABLE`, `IO_ERROR`,
`BUSY`, and `TOO_LARGE` (12 values; `BUSY`/`TOO_LARGE` are Cycle-4 additions, E01-22, added once the
per-direction offer/transfer caps and the size cap below were defined).

### Handshake

1. The sender computes `sha256 = SHA-256(whole source file bytes)` in a single streaming pass
   *before* building `FileOffer` — the digest is of the entire file as it exists on the sender's
   side at offer time, never recomputed per chunk.
2. The sender sends `FileOffer{id, name, size, mime, sha256}`.
3. The receiver either sends `FileAccept{id}` (user action, or auto-accept — "Cycle 4 caps"
   below) or `FileReject{id, reason}` (user declined, or a cap violation below). Either is
   terminal for a rejection: no further FILES message referring to `id` is valid once
   `FileReject` has been sent for it.
4. Once `FileAccept` has been received, the sender streams `FileChunk{id, seq, offset, data}`
   frames in contiguous `seq` order (0-based) until the whole file has been sent — see "Chunking"
   below.
5. The sender sends `FileComplete{id}` once every chunk has been sent. The receiver verifies its
   reassembled file's SHA-256 against `FileOffer.sha256`; a mismatch is reported back with
   `FileCancel{id, reason: HASH_MISMATCH}` (the transfer is not silently kept).
6. Either side may send `FileCancel{id, reason}` at any point after step 2 to abort the transfer
   mid-flight, for any `TransferReason`; it is terminal for `id`, like `FileReject`.
7. A receiver that already retains a partial temp file for `id` from a previously interrupted
   transfer sends `FileResumeRequest{id, from_offset}` instead of `FileAccept` — see "Resume"
   below — and the sender resumes chunk transmission from `from_offset` rather than restarting at
   `seq = 0`.

### Chunking

`FileChunk.data` is capped at 262,144 bytes (256 KiB, 2^18) per chunk. `seq` is 0-based and
contiguous; `offset` MUST equal `seq * 262144`. A receiver validates every incoming chunk against
its own current reassembly state, independent of what the sender claims `seq`/`offset` to be:

- A chunk whose `offset` is not equal to the receiver's current reassembled length, or whose
  `offset + len(data)` would exceed `FileOffer.size`, is a `PROTOCOL_VIOLATION`
  (`FileCancel{id, reason: PROTOCOL_VIOLATION}`) — never silently clamped or reordered.
- A chunk whose `data` is over the 262,144-byte cap is likewise rejected as a
  `PROTOCOL_VIOLATION`, never truncated.

### Unanswered-offer timeout

A `FileOffer` the receiver has neither accepted, rejected, nor resumed within 300 s of receipt is
rejected by the receiver with `FileReject{id, reason: TIMEOUT}`. This is a receiver-side timer
only; the sender does not independently time out a pending offer.

### Resume semantics

A receiver that still retains a partial temp file for a previously interrupted transfer `id`
reports `from_offset` in `FileResumeRequest` as that temp file's retained length, rounded *down*
to the nearest 262,144-byte boundary (i.e. `from_offset = floor(retained_length / 262144) *
262144`) — never the exact retained byte count, so the sender always resumes on a chunk boundary
and never has to split a chunk. The sender resumes streaming `FileChunk` frames starting at
`seq = from_offset / 262144`.

A retained temp file expires 24 h after its last write; a `FileResumeRequest` (or any other FILES
message) naming an `id` whose temp file has already expired, or that never existed, is rejected
with `FileReject{id, reason: UNKNOWN_TRANSFER}` — the sender has no choice but to restart the
transfer as a fresh `id` in that case.

### Cycle 4 caps (E01-22)

Restated here from §10 ("Feature caps") as the single source of truth for the FILES channel:

- `FileOffer.size` MUST be <= 64 GiB (2^36 bytes), else the receiver responds
  `FileReject{id, reason: TOO_LARGE}` without prompting the user.
- `FileOffer.name`'s raw, pre-sanitization byte length MUST be <= 1024 UTF-8 bytes, else the
  receiver responds `FileReject{id, reason: INVALID_NAME}` (the E40-02 filename-sanitization rule
  applies only to a name that already passes this length cap).
- `FileOffer.mime` MUST be <= 255 bytes, else the receiver responds
  `FileReject{id, reason: INVALID_NAME}`.
- A receiver holds at most 4 unanswered offers and 2 active transfers per direction at once;
  an offer arriving in excess of either limit is rejected `FileReject{id, reason: BUSY}`
  immediately, without ever prompting the user.
- Auto-accept (sending `FileAccept` without a user prompt) applies only to offers with
  `size <= 1 GiB` (2^30 bytes), and only when the receiver's auto-accept setting is enabled
  (opt-in, off by default); an offer over that cap always requires a manual accept regardless of
  the setting.

### Filename sanitization

*(E40-02 · PRD F-7.1 · UC-14, UC-15)*

A receiver MUST sanitize every incoming `FileOffer.name` before using it as a destination
filename, independently of the sender, which is never trusted. The name passes the 1024-byte
pre-sanitization cap above first. Steps, in this exact order:

1. If the name contains U+0000, reject with `FileReject{id, reason: INVALID_NAME}`; no later step runs.
2. Split on `/` and `\` and keep only the last component (possibly empty).
3. Normalize to NFC.
4. Remove the bidi controls U+202A–U+202E and U+2066–U+2069.
5. Replace every other C0 control (U+0001–U+001F), U+007F and `:` with `_`.
6. Strip all leading `.`.
7. If the result is empty, use `file-<first 8 characters of FileOffer.id>`.
8. If the part before the first `.` equals (case-insensitively) `CON`, `PRN`, `AUX`, `NUL`,
   `COM1`–`COM9` or `LPT1`–`LPT9`, prefix `_`.
9. If the UTF-8 length exceeds 255 bytes, truncate the stem (everything before the last `.`) on a
   code-point boundary, keeping the extension (the last `.` and what follows), until the UTF-8
   length is at most 255 bytes. If the extension alone leaves no room, truncate the whole name
   instead.

The result is only a filename; collision handling and the destination directory are the
receiver's concern. `protocol/vectors/filenames.json` (E40-02) holds the shared vectors; both
platforms' receivers (E40-16 Android, E40-17 macOS) MUST produce the vector's `expected.filename`
(or `expectedError: invalidName`) for every case.

### Photos (E41-01)

*(PRD F-7.4 · UC-17, AC-19 · no separate PHOTOS channel, E01-04 decision — these messages ride
FILES like every message above)*

The phone's photo library is browsed, thumbnailed, and fetched in full resolution over the same
FILES channel as file transfers, using six additional message types defined in
`protocol/proto/tandem/v1/photos.proto`: `PhotoPage{cursor, limit}`,
`PhotoPageResult{items: repeated PhotoMeta{id, taken_at, width, height}, next_cursor, access}`,
`ThumbRequest{id, max_px}`, `ThumbResult{id, png_bytes}`, `OriginalRequest{id, transfer_id}`, and
`PhotoError{kind, ref, reason}`.

- **Paging.** `PhotoPage.cursor` is opaque and phone-assigned: empty on the first request of a
  session, and on every later request set to the exact `next_cursor` a previous
  `PhotoPageResult` returned. The Mac MUST NOT construct, parse, or otherwise interpret a cursor's
  contents — it is a stable, round-trippable token only. `next_cursor` is empty when the returned
  page is the library's last. `limit` MUST be clamped by the phone to 1..200 inclusive; `limit = 0`
  (proto3's default) means "unset" and is treated as 100.
- **Access.** Every `PhotoPageResult` reports the phone's current media-library access grant in
  `access` (`FULL`, `PARTIAL`, or `NONE`) so the Mac can distinguish an empty or short page caused
  by `PARTIAL`/`NONE` access from one caused simply by reaching the end of the library — access can
  change between requests, since the user can grant or revoke it from system settings at any time.
- **Thumbnails.** `ThumbRequest.max_px` MUST be clamped by the phone to 32..384 inclusive. This
  range is chosen so that a worst-case uncompressed RGB PNG at the upper bound (384x384x3 bytes,
  before PNG's own compression) still fits within a single 1 MiB `Envelope` frame
  (`#framing-and-envelope`) — `ThumbResult.png_bytes` is never itself chunked or split across
  frames. `ThumbResult` returns the photo resized so its longest edge is <= the clamped `max_px`.
- **Originals.** `OriginalRequest{id, transfer_id}` asks for the full-resolution original of the
  photo named by `id`. The phone answers by sending a real `files.proto` `FileOffer` whose own
  `id` field equals `transfer_id` — never a new message type — and the transfer then proceeds
  through the normal FILES "Handshake" above (accept/chunk/complete, or reject/cancel) exactly like
  any other file transfer.
- **Sender interleaving.** The FILES sender interleaves its outgoing frames per logical stream
  (round-robin between any in-flight `FileChunk` transfer and pending `ThumbResult`/
  `PhotoPageResult` responses) so that a large in-flight original-photo or file transfer never
  blocks a `ThumbResult` or `PhotoPageResult` for more than one chunk's worth of latency. This
  interleaving is implemented at the connection-writer level (E40-03/E40-04); this section
  documents only the protocol-level expectation, not the scheduling algorithm itself.
- **Errors.** `PhotoError{kind, ref, reason}` reports that a `PhotoPage`, `ThumbRequest`, or
  `OriginalRequest` failed. `kind` (`PAGE`, `THUMB`, `ORIGINAL`) says which request type failed;
  `ref` is that failed request's own identifying value — the rejected `cursor` for `PAGE` (empty
  when the very first page request failed), or the photo `id` for `THUMB`/`ORIGINAL`. `reason` is
  one of `NOT_FOUND`, `ACCESS_DENIED`, `INVALID_CURSOR`, or `BUSY`.
- **Cycle 4 caps (E01-22).** `BUSY` is a Cycle-4 addition: a receiver holds at most 8 outstanding
  `ThumbRequest`s and at most 1 outstanding `PhotoPage` per peer at once; a request arriving in
  excess of either limit is rejected `PhotoError{kind, ref, reason: BUSY}` immediately.

### Conformance

`protocol/vectors/files-encoding.json` (E15-01, E15-02) includes: a `FileOffer`/`FileAccept` pair
that decodes to identical fields on both codecs; a `FileResumeRequest` whose `from_offset` decodes
exactly; a `FileReject` for every one of the 12 `TransferReason` values (including `BUSY` and
`TOO_LARGE`) round-tripping on both codecs; and a `FileChunk` with a 262,145-byte `data` payload —
one byte over the 262,144-byte cap above — rejected as oversized by both codecs.

`protocol/vectors/photos-encoding.json` (E41-01) includes: a `PhotoPageResult` with
`access: PARTIAL` decoding identically on both codecs; a `ThumbResult` whose `png_bytes` decodes to
identical bytes on both codecs; an `OriginalRequest` whose `transfer_id` decodes exactly; and a
`PhotoError` for every one of the 4 `PhotoErrorReason` values (`NOT_FOUND`, `ACCESS_DENIED`,
`INVALID_CURSOR`, `BUSY`) round-tripping on both codecs.

---

## Contacts channel

*(E51-01 · PRD F-8.3 · UC-18, UC-19, UC-20, UC-21 · invariants 7)*

The CONTACTS channel (`Channel.CHANNEL_CONTACTS`, §4) syncs the phone's contacts store to the Mac:
a full or incremental pull of contact records, plus tombstones for contacts the phone has deleted
since the last sync. It carries two message types, each sent directly as the Envelope payload (no
wrapper message): `ContactsSyncRequest{since_updated_at_ms}` and
`ContactsSyncResponse{status, contacts, deleted_contact_ids, watermark_ms, complete}`
(`protocol/proto/tandem/v1/contacts.proto`). A `Contact{contact_id, display_name, phone_numbers,
emails, photo_thumbnail, updated_at_ms}` carries a contact record; `Contact.PhoneNumber{number,
normalized_e164, type}` and `Contact.Email{address, type}` are its repeated child records, and
`ContactAddressType` (`HOME`/`WORK`/`MOBILE`/`OTHER`, plus `UNSPECIFIED`) labels both. `contact_id`
is phone-assigned and stable for a given contact; it is never reused for a different contact once
sent.

`display_name`, `PhoneNumber.number` and `Email.address` are untrusted peer input and MUST be
sanitized per `#untrusted-peer-strings-display-sanitization` (E01-23) before ever being rendered.

### Sync

1. The Mac sends `ContactsSyncRequest{since_updated_at_ms}` to ask for every contact the phone's
   store has created or modified since that timestamp; `since_updated_at_ms = 0` requests a full
   sync of every contact.
2. The phone responds with one or more `ContactsSyncResponse` pages. `status` is `OK` for a normal
   response; `contacts` and `deleted_contact_ids` are populated only when `status = OK`.
   `deleted_contact_ids` names contacts removed from the phone's store since `since_updated_at_ms`
   (tombstones) so the Mac can remove its own copies rather than treating an absence as "unchanged".
3. `complete` is `false` while more pages for this sync remain and `true` on the last page of the
   sync. The Mac does not send a further `ContactsSyncRequest` mid-sync; the phone alone decides
   how contacts are paginated across `ContactsSyncResponse` messages.
4. `status = PERMISSION_REQUIRED` means the phone has not granted contacts-read permission; such a
   response carries empty `contacts` and `deleted_contact_ids` and `complete = true` (there is
   nothing more to page). `status = FULL_RESYNC_REQUIRED` tells the Mac its retained watermark is
   stale (e.g. the phone's contacts store was reset or reinstalled) and it MUST discard its local
   contacts and resend `ContactsSyncRequest{since_updated_at_ms: 0}`.

### Watermark

`watermark_ms` is Mac-authoritative: the Mac persists the `watermark_ms` from the last page of a
completed sync (`complete = true`) and sends it back as the next `ContactsSyncRequest`'s
`since_updated_at_ms` — the phone never persists sync state of its own across connections. Every
`ContactsSyncRequest` therefore carries `since_updated_at_ms` explicitly, never an implicit
"since last connection".

### Thumbnail cap

`Contact.photo_thumbnail`, when present, MUST be a JPEG no larger than 96 px on its longest edge
and no larger than 32,768 bytes (32 KiB). The cap is expressed in bytes, not pixels: a receiving
parser decodes `photo_thumbnail` as an opaque `bytes` field and cannot itself check the JPEG's
decoded pixel dimensions, only its encoded byte length — the pixel-dimension rule is enforced by
the sender's own thumbnail-generation step, not by the receiver. A `Contact` whose
`photo_thumbnail` exceeds 32,768 bytes MUST be rejected by the receiving platform's own
post-decode validator before the thumbnail is ever displayed or persisted — never silently
truncated or accepted oversized.

### Conformance

`protocol/vectors/contacts-encoding.json` (E15-01, E15-02) includes: a full `Contact` record (two
phone numbers, one email, a `photo_thumbnail`) round-tripping identically on both codecs; a
`ContactsSyncRequest`; a `ContactsSyncResponse` with three `deleted_contact_ids` and zero
`contacts`, decoding identically on both codecs; and a `Contact` with a `photo_thumbnail` one byte
past the 32,768-byte cap above, rejected by both platforms' validators.

---

## SMS channel

*(E50-01 · PRD F-8.1, F-8.2 · UC-18, UC-19, AC-19 · invariant 7)*

The SMS channel (`Channel.CHANNEL_SMS`, §4) syncs the phone's SMS store to the Mac and carries
outgoing sends. It uses five message types, each sent directly as the Envelope payload (no wrapper
message; `Envelope.payload` fields 70-74, 75-79 held for future extensions):
`SmsSyncRequest{since_id, backfill_before_id, page_size}`,
`SmsSyncResponse{status, threads, messages, high_watermark_id, backfill_cursor_id,
backfill_complete}`, `SendSmsRequest{client_message_id, thread_id, address, subscription_id, body}`,
`SendSmsStatus{client_message_id, state, error_code, provider_message_id}` and
`SimList{subscriptions: Subscription{subscription_id, display_name, slot_index}}`
(`protocol/proto/tandem/v1/sms.proto`). `SmsThread{thread_id, address, snippet, last_message_at_ms,
unread_count}` and `SmsMessage{id, thread_id, address, body, timestamp_ms, type, subscription_id,
delivery_status}` are embedded in `SmsSyncResponse` only. `SmsMessage.id` is the phone provider's
`_id` and defines the cursor space below.

`address`, `snippet` and `body` are untrusted peer input and MUST be sanitized per
`#untrusted-peer-strings-display-sanitization` (E01-23) before ever being rendered. They are
message content: invariant 7 forbids logging them in release builds.

### Cursors

Cursors are Mac-authoritative: the Mac persists `high_watermark_id` and `backfill_cursor_id` from
the last page it processed and sends them back; the phone keeps no sync state across connections.
At most one `SmsSyncRequest` is in flight per connection; a new one supersedes the previous
(§10, E01-22).

- **Fresh sync.** `since_id = 0` and `backfill_before_id = 0`. The phone snapshots the maximum
  provider `_id` M, sends rows backfilling in descending `_id` order starting below-and-including
  M, and sets `high_watermark_id = M` on every page.
- **Forward sync.** Otherwise the phone first sends every row with `_id > since_id` in ascending
  order, then continues the backfill with rows whose `_id < backfill_before_id` (descending).
- **Backfill.** Each page sets `backfill_cursor_id` to the smallest `_id` it has sent so far; the
  Mac echoes it as the next request's `backfill_before_id`. `backfill_complete = true` on the page
  that reaches the oldest row; later requests then use only `since_id`.
- `page_size` bounds the number of `messages` in one `SmsSyncResponse` page.
- During a live session the phone may also send unsolicited incremental `SmsSyncResponse` pushes: they
  carry only new rows/threads and `high_watermark_id`; unset `backfill_cursor_id` and
  `backfill_complete` mean "backfill state unchanged", and receivers MUST NOT treat them as a reset.
- `status = PERMISSION_REQUIRED` is returned, with no `threads` or `messages`, when the phone has
  not granted READ_SMS; `status = OK` otherwise.

### Send

1. The Mac sends `SendSmsRequest` with a Mac-generated UUID `client_message_id`; `thread_id = 0`
   means a new conversation; `subscription_id` selects a SIM from the latest `SimList`.
2. The phone answers with zero or more `SendSmsStatus`, each echoing `client_message_id` so the
   Mac matches its optimistic bubble without guessing. States progress `SENDING` -> `SENT` ->
   `DELIVERED`; `FAILED` may follow any non-terminal state and sets `error_code`.
3. `provider_message_id` is the `SmsMessage.id` the provider assigned (0 until known), letting the
   Mac reconcile the sent row with the next sync.
4. A `body` over 1600 characters fails with `TOO_LONG`, and more than 10 sends in a rolling 60 s
   fail with `RATE_LIMITED`; both are rejected before `SmsManager` is called (§10).
5. A `subscription_id` of 0 means the phone's default SMS subscription. If it is not valid, or
   the phone has two or more active SIMs and no valid default, the send fails with
   `SUBSCRIPTION_REQUIRED`; a nonzero `subscription_id` absent from the active subscriptions
   fails with `INVALID_SUBSCRIPTION`. Neither reaches `SmsManager`; the phone never guesses a SIM.

### SIM list

The phone sends `SimList` on connect and again whenever the set of active subscriptions changes
(publish-on-change); the Mac never requests it. The newest `SimList` replaces the previous one.

### Non-default-SMS-app behavior

*(E50-06 · PRD F-8.2 · UC-19)*

Since Android 4.4 only the holder of the default-SMS-app role may insert, update or delete rows in
the SMS provider. Tandem does not request that role in v1 (revisit in v2; mark-as-read and
delete-on-phone stay out of scope until then). Consequences:

- **The system writes Sent rows.** For an app that is not the default, the platform itself records
  messages sent through `SmsManager.sendTextMessage`/`sendMultipartTextMessage` in the provider, so
  Tandem-originated sends appear as Sent rows and flow back through incremental sync (§ Cursors,
  E50-03) like any other message.
- **Tandem cannot change provider rows.** It reads via `query()` only (`READ_SMS`); it cannot mark
  messages read, delete them, or repair a missing row.
- **Reconciliation.** The Mac tracks each send by `client_message_id` and, when a `SendSmsStatus`
  reports `provider_message_id` (the `_id` of the system-written row), merges that row with its
  optimistic outbound message instead of storing a duplicate (E50-04, E50-14).
- **Local-only fallback.** If no provider row is reported (an OEM deviation from the documented
  behavior), the Mac keeps its own row as local-only send history.

Evidence: the E50-04 manual gate `smsSender_nonDefaultAppSend_systemWritesOneSentProviderRow` in `docs/testing/manual-gates.md` records the device model and
Android version on which a non-default send produced exactly one Sent provider row.

### Conformance

`protocol/vectors/sms-encoding.json` (E15-01, E15-02) includes: a full `SmsMessage` decoding
identically on both codecs; a `SendSmsStatus` for every `SendSmsState` value (`SENDING`, `SENT`,
`DELIVERED`, `FAILED`); an `SmsSyncResponse` carrying `high_watermark_id`, `backfill_cursor_id` and
`backfill_complete = false`; and an SMS Envelope frame whose length prefix exceeds the 1 MiB
maximum (§3), rejected from the 4 prefix bytes alone before any body buffer is allocated.

---

## Calls channel

*(E52-01 · PRD F-8.4 · UC-20, UC-21, AC-19 · invariant 7)*

The Calls channel (`Channel.CHANNEL_CALLS`, §4) mirrors the phone's call state to the Mac and
carries the Mac's call controls. It uses four message types, each sent directly as the Envelope
payload (no wrapper message; `Envelope.payload` fields 90-93, 94-99 held for future extensions):
`CallEvent{call_id, direction, state, address, normalized_e164, timestamp_ms}`,
`CallAction{request_id, call_id, action}`, `PlaceCallRequest{request_id, address, subscription_id}`
and `CallActionResult{request_id, call_id, success, error_code}`
(`protocol/proto/tandem/v1/calls.proto`).

`address` and `normalized_e164` are phone numbers and therefore message content: invariant 7 forbids
logging them in release builds. `address` is untrusted peer input and MUST be sanitized per
`#untrusted-peer-strings-display-sanitization` (E01-23) before ever being rendered. The caller name
is resolved on the Mac (E51-04) from `normalized_e164` and is never sent.

### Call events

The phone sends a `CallEvent` on every call state change (phone -> Mac only). `call_id` is generated
by the phone per RINGING/DIALING-to-ENDED cycle and is stable across every event of that cycle; a
later call gets a new `call_id`. States progress:

- incoming: `RINGING` -> `ACTIVE` -> `ENDED`
- outgoing: `DIALING` -> `ACTIVE` -> `ENDED`
- `ENDED` may follow `RINGING` or `DIALING` directly (missed, declined, cancelled or failed call).

`ENDED` is terminal for its `call_id`. `normalized_e164` is the E.164 form of `address`, empty when
it cannot be normalized. `timestamp_ms` is Unix epoch milliseconds.

### Call actions

The Mac sends `CallAction` with a Mac-generated `request_id`: `ANSWER` or `DECLINE` for a `RINGING`
call, `HANGUP` for a `DIALING` or `ACTIVE` call. The phone answers every `CallAction` and every
`PlaceCallRequest` with exactly one `CallActionResult` echoing `request_id`. On success
`success = true` and `error_code` is `UNSPECIFIED`; on failure `success = false` and `error_code`
is one of:

| `error_code` | Meaning |
|---|---|
| `UNKNOWN_CALL` | `call_id` does not name a call the phone knows. |
| `NOT_RINGING` | `ANSWER`/`DECLINE` for a call that is not `RINGING`. |
| `NO_ACTIVE_CALL` | `HANGUP` for a call that is neither `DIALING` nor `ACTIVE`. |
| `PERMISSION_DENIED` | The phone has not granted the permission the action needs. |
| `INVALID_SUBSCRIPTION` | `PlaceCallRequest.subscription_id` is not an active subscription in the latest `SimList` (§14). |
| `NEEDS_PHONE_TAP` | The phone OS refuses to perform the action without a tap on the phone. |
| `INVALID_NUMBER` | `PlaceCallRequest.address` fails the address rule below. |
| `RATE_LIMITED` | A second `PlaceCallRequest` arrived within 5 s of the previous one. |

`call_id` in the result is empty when no call is involved.

### Place call

`PlaceCallRequest{request_id, address, subscription_id}` asks the phone to dial. `subscription_id`
selects a SIM from the latest `SimList` (§14); `0` means the phone's default.

- `address` MUST match `^\+?[0-9]{3,20}$` after removing spaces and dashes. MMI/USSD strings
  (`*`, `#`) and pause/wait characters (`,`, `;`) are therefore rejected with `INVALID_NUMBER`.
- At most one `PlaceCallRequest` per 5 s is accepted; a request within 5 s of the previous one is
  rejected with `RATE_LIMITED` (§10, E01-22).
- Both rejections are made before any call is placed.

### Conformance

`protocol/vectors/calls-encoding.json` (E15-01, E15-02) includes: an incoming `RINGING`
`CallEvent` round-tripping to its golden bytes; the `RINGING` -> `ACTIVE` -> `ENDED` event sequence
of one call decoding identically on both codecs; and failed `CallActionResult`s carrying
`UNKNOWN_CALL`, `INVALID_NUMBER` and `RATE_LIMITED`.

---

## Key rotation

Normative definition of `rotation.proto` (E70-01; `docs/planning/decisions.md` D-24, D-34, D-67,
D-74). Rotation replaces one side's pinned identity key (SPKI, §1) with a new one over an already
authenticated control session. It is key hygiene, **not compromise recovery**: a holder of a stolen
old key can itself rotate, so a suspected compromise is handled by unpair and re-pair (AC-15, E02-01).

### Messages

All four ride `CONTROL` as `Envelope` payloads 110–113 and are legal only on a control session that
has reached Ready (§ Channel binding). On a pairing-candidate connection before `PairAccepted` any of
them is a wrong payload: the receiver closes with `PAIRING_FAILED` (§2) and sends no `RotationReject`.

- `RotationChallenge { challenge }` — exactly 32 CSPRNG bytes, sent once per session by each side
  as defined in § Channel binding (`cb`) (D-74).
- `KeyRotation { newSpkiDer, sigOldKey, sigNewKey }` — sent by the rotating peer (the initiator)
  after it received the other side's `RotationChallenge` on this session. `newSpkiDer` is a DER
  SubjectPublicKeyInfo (§1).
- `RotationAck {}` — the receiver accepted and pinned (or stored pending, below) the new key.
- `RotationReject { reason }` — `INVALID_SIGNATURE`, `UNAUTHENTICATED_SESSION` (only on a connection
  that completed mTLS but whose peer is not pinned; pre-`PairAccepted` is the wrong-payload close above), `NOT_PRIMARY_PIN`,
  `DUPLICATE_KEY`, `ROTATION_UNAVAILABLE`. `UNSPECIFIED` is never legal on the wire. A reject does
  not close the connection and leaves the trust store unchanged.

### Transcript and signatures

```
transcript = ASCII("tandem-rotate-v1") || LP(oldSpkiDer) || LP(newSpkiDer) || LP(cb)
```

`LP(x) = u16be(len(x)) || x`, as in §2. `oldSpkiDer` is the SPKI of the certificate that
authenticated this session's TLS handshake (never a message field); `cb` is the **receiver's**
`RotationChallenge` for this session. `sigOldKey` and `sigNewKey` are ECDSA P-256 / SHA-256 over the
transcript, ASN.1 DER encoded, made by the old and the new private key. The old-key signature
authorizes the rotation; the new-key signature proves possession so a device cannot claim someone
else's public key. Because `cb` is fresh per session, a `KeyRotation` captured on one session fails
on any other.

The receiver MUST, in this order:

1. reject `UNAUTHENTICATED_SESSION` if the session has not completed mTLS with a pinned peer;
2. idempotent re-send (below): if `newSpkiDer` is already that peer's primary or pending pin and the
   session was authenticated by that peer's primary or grace pin, send `RotationAck` and stop;
3. reject `NOT_PRIMARY_PIN` unless that peer's **current primary** pin authenticated the session (a
   grace pin never authorizes a new rotation);
4. reject `ROTATION_UNAVAILABLE` if a Mac has a pairing window open or a rotation for this peer is
   already pending;
5. reject `INVALID_SIGNATURE` unless `newSpkiDer` is exactly the 91-byte DER SubjectPublicKeyInfo of an
   uncompressed ECDSA P-256 key (§1: `id-ecPublicKey`, `prime256v1`, `0x04` point); other curves,
   compressed points and any other length or encoding fail here, before any signature work;
6. verify both signatures (any malformed, truncated or non-verifying signature is
   `INVALID_SIGNATURE`);
7. reject `DUPLICATE_KEY` if `newSpkiDer` equals any existing primary or grace pin in its trust store;
8. pin (or store pending) and send `RotationAck`.

The challenge is consumed by the first `KeyRotation` that reaches signature verification (step 6)
and is never reused.

### Idempotent re-send

A re-sent `KeyRotation` whose `newSpkiDer` the receiver already holds as that peer's primary pin or
pending pin, on a session authenticated by that peer's primary or grace pin, is acknowledged with
`RotationAck` without re-verifying against the consumed challenge and without any state change. It is
checked first (step 2) so the `NOT_PRIMARY_PIN`, `ROTATION_UNAVAILABLE` and `DUPLICATE_KEY` rejects
never fire on a retry. It applies to:

- a phone-initiated rotation whose `RotationAck` was lost: the Mac now holds the new key as primary and
  the phone reconnects on the old key, which is a grace pin on the Mac;
- a Mac-initiated rotation whose `RotationAck` was lost: the phone holds the new Mac key as pending and
  the Mac reconnects on its old key, still the phone's primary.

### Grace pin

After the swap the old SPKI is kept as a grace pin. It stays accepted for at most one subsequent
session, and is purged as soon as either that session closes or a session authenticated with the new
SPKI completes `VersionHello`. It also expires 7 days after the swap, so a lost `RotationAck` or a
peer that never reconnects cannot keep the old key alive.

### Mac-initiated rotation (two-phase)

A Mac key rotation (D-34) must not lock out any paired phone: the Mac listener presents one identity.

1. The Mac sends `KeyRotation` to each paired phone as it connects. The phone verifies as above,
   stores the new Mac key as a **pending** pin (not yet trusted for connections) and replies
   `RotationAck`.
2. The Mac switches its listener identity only after every paired phone has acked.
3. A phone promotes the pending pin to primary when a handshake presents it; the grace rule above
   starts at that moment for the old Mac pin.
4. A pending pin never presented is purged after 30 days.
5. After 7 days without every phone acking, the Mac offers **Finish** (unpair the phones that have
   not confirmed) or **Cancel**; the Mac never switches keys silently.

### Timeouts and scheduling

- The initiator MUST treat a missing `RotationAck`/`RotationReject` within **30 s** of sending
  `KeyRotation` as a failed attempt and keep using the old key.
- Scheduled rotation: a setting with values Off, 90, 180 or 365 days, default 365 days since the
  last rotation (or pairing). A scheduled rotation fires only over an authenticated Ready session and
  otherwise defers until the next one.

### Conformance

`protocol/vectors/rotation-encoding.json` (E70-01; E15-01, E15-02) includes: `RotationChallenge`,
`RotationAck` and each `RotationReject` reason round-tripping to golden bytes; a `KeyRotation` whose
old-key and new-key signatures verify over the transcript; and `KeyRotation`s that fail verification
(`INVALID_SIGNATURE`) for a tampered `newSpkiDer`, a `sigOldKey` made by the new key, a `sigOldKey`
made by an unrelated key, a truncated DER signature, signatures made over another session's
`RotationChallenge`, a `sigNewKey` made by a key other than `newSpkiDer`, and a `newSpkiDer` that is
not a 91-byte uncompressed P-256 SPKI (a P-384 key, a compressed-point P-256 key). The vector format
carries no receiver trust-store state, so the ordered receiver algorithm is tested in E70-04/E70-05:
replay of a consumed challenge, the idempotent re-send on a grace-pin session (phone-initiated) and on
a pending-pin session (Mac-initiated) acking before `NOT_PRIMARY_PIN`/`ROTATION_UNAVAILABLE`/
`DUPLICATE_KEY`, and each reject reason.

## Focus sync

F-10.2 (design note `docs/spikes/focus-dnd-sync.md`, E72-03). The Mac's Focus state drives the phone's
Do Not Disturb interruption filter. Direction is Mac to phone only: the phone never reports its own
filter. Both messages (`focus.proto`, E72-04) ride the `CONTROL` channel as `Envelope` payloads 120
(`FocusState`) and 121 (`FocusSyncCapability`), on an authenticated control session that has reached
Ready.

### FocusState

- `FocusState { on }` is sent by the Mac on every Focus change.
- `on = true`: a receiver holding notification-policy access records the interruption filter
  currently active (only if sync has not already recorded one) and sets the priority-only filter.
- `on = false`: a receiver that previously applied a filter restores the recorded filter and forgets
  it; a receiver that never applied one changes nothing.
- A receiver without notification-policy access MUST NOT change the interruption filter and MUST
  answer `FocusSyncCapability { available: false }`. A receiver that applies the state sends nothing.
- `FocusState` carries no secret material; invariants 1 and 8 are inherited from the control session.

### FocusSyncCapability

`FocusSyncCapability { available }` is sent by the phone only; `available = false` tells the Mac that
the phone cannot apply Focus. The Mac stops sending `FocusState` until it sees `available = true`.

### Conformance

`protocol/vectors/focus-encoding.json` (E72-04; E15-01, E15-02) includes `FocusState` (on and off) and
`FocusSyncCapability` (unavailable and available) round-tripping to golden bytes on both codecs.
