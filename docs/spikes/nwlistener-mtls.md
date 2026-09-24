# Spike E03-01 — NWListener mTLS, TLS 1.3-only, client cert required

Issue: GitHub #91 / backlog `E03-01` (`docs/planning/backlog/phase-0.yaml`). Branch
`e03-01-nwlistener-spike`. Code lives in `spikes/e03-01-nwlistener/` (throwaway SwiftPM package,
not shipped). Findings feed ADR-003 (E02-04) and the channel-binding outcome (E03-04, cycle-4
decision D-15/D-35).

Machine: macOS 26.5 (Xcode 26.6, Swift 6.3.3), Network.framework / Security.framework from the
MacOSX26.5 SDK. `openssl` used for cross-checks is Homebrew OpenSSL 3.6.4 (the system `/usr/bin/openssl`
is LibreSSL 3.3.6 and also works for most of these checks, but Homebrew's is used throughout for a
standards-reference implementation).

## Go / no-go summary

| # | Acceptance item (from phase-0.yaml E03-01) | Result | Evidence |
|---|---|---|---|
| 1 | TLS 1.2 ClientHello rejected | **GO** | §4: 10/10, fatal `protocol_version` alert, 0 established sessions |
| 2 | Unpinned client cert rejected inside verify block, 0 app bytes | **GO** | §2: 10/10 `match=false`, 0 app-data events on the server |
| 3 | No client cert rejected | **GO** (server); gotcha on client | §3: server 10/10 fails fast; client reports `.waiting`, not `.failed` |
| 4 | No session ticket / resumption artifact produced | **GO** — stronger than asked | §6: 0/10 tickets issued even with tickets *explicitly enabled* |
| 5 | Verify block runs before `.ready` | **GO** | §8: structural (API contract) + consistent log ordering across all runs |
| 6a | Exporter (`sec_protocol_metadata_create_secret`) matches `openssl -keymatexport` | **GO** | §9: bit-exact match, reproduced twice |
| 6b | Pinned cert + mismatched private key fails | **NOT DIRECTLY EXERCISED** | §10: openssl/Python both refuse locally before dialing; argued analytically |
| 6c | ALPN `tandem/1` enforced | **PARTIAL NO-GO** | §5: correct/wrong ALPN handled correctly, but a client that sends **no ALPN extension at all** is accepted (`alpn=none`) instead of failing |
| 6d | Listener can read remote endpoint pre-handshake; 10 s handshake deadline enforceable | **GO** | §7: endpoint readable at TCP-accept time; deadline cancels a stalled pre-TLS connection |

**Overall recommendation for ADR-003 (E02-04): GO for Network.framework as the macOS TLS stack**,
with one required follow-up for E01-01/E12-04: add an explicit application-level ALPN check in the
`.ready` handler (`metadata.negotiatedALPN == "tandem/1"`, else cancel) because Network.framework's
own enforcement only covers *mismatched* ALPN, not *absent* ALPN. This is a small, well-understood
gap, not a stack-level blocker, so **E03-05 (swift-nio-ssl fallback) is not needed**.

## What works — API calls used

- `NWListener` bound to a literal loopback endpoint via `NWParameters.requiredLocalEndpoint`
  (`NWListener(using:)`, no separate `on:` port — passing both throws `POSIXErrorCode(rawValue: 22)`).
- TLS 1.3-only: `sec_protocol_options_set_min_tls_protocol_version` **and**
  `_set_max_tls_protocol_version`, both `.TLSv13`.
- Client cert required: `sec_protocol_options_set_peer_authentication_required(_, true)`.
- Pin check: `sec_protocol_options_set_verify_block` → `sec_trust_copy_ref(trust).takeRetainedValue()`
  → `SecTrustCopyCertificateChain` → leaf at index 0 → `SecCertificateCopyKey` →
  `SecKeyCopyExternalRepresentation` (65-byte `0x04 ‖ X ‖ Y` for P-256) → prepend the fixed 26-byte
  SPKI DER header → SHA-256 → `timingsafe_bcmp` (Darwin, constant-time).
- ALPN: `sec_protocol_options_add_tls_application_protocol(_, "tandem/1")`.
- Ticket/resumption control: `sec_protocol_options_set_tls_tickets_enabled` (server-side: whether
  to *issue* tickets) and `sec_protocol_options_set_tls_resumption_enabled` (whether to *offer/accept*
  resumption). Both set `false` in the intended production configuration.
- Channel binding / exporter: `sec_protocol_metadata_create_secret(metadata, "EXPORTER-Channel-Binding".utf8.count, "EXPORTER-Channel-Binding", 32)`,
  read via `NWConnection.metadata(definition: NWProtocolTLS.definition)` →
  `.securityProtocolMetadata`. Returns `dispatch_data_t`; bridge with `secret as DispatchData` then
  `Data(dispatchData)` (a direct `Data(secret)` init does not compile — `__DispatchData` isn't
  `Sequence`).
- Identity: self-signed P-256 certs generated with `openssl ecparam`/`openssl req`, packaged as
  PKCS#12 (`openssl pkcs12 -export -legacy`), imported via `SecPKCS12Import` into a **temporary,
  on-disk keychain** created with `SecKeychainCreate` (never the login keychain), yielding a
  `SecIdentity` directly from `kSecImportItemIdentity` — no `SecItemCopyMatching` round-trip needed.

## Gotchas (in the order they cost the most time)

1. **`NWConnection.start(queue: .main)` deadlocks a synchronous CLI.** A test harness that blocks
   its main thread on a semaphore (as this spike's client does, to turn async callbacks into a
   simple exit code) must **not** hand the connection `.main` as its queue — nothing ever drains
   the main dispatch queue, so every callback (state updates, `send`/`receive` completions) silently
   never fires. The connection just sits until the outer timeout. This is indistinguishable from a
   real network hang unless you know to look for it. Fix: use a dedicated
   `DispatchQueue(label:)` for the connection when the caller manages its own run loop by blocking.
   (`Sources/nwlistener-spike/Client.swift`.)

2. **`sec_trust_copy_ref` returns `Unmanaged<SecTrust>`**, not `SecTrust`, despite the header not
   marking it `SEC_RETURNS_RETAINED`. Needs `.takeRetainedValue()`.

3. **OpenSSL 3's default PKCS#12 encryption (PBES2 + AES-256, SHA-256 MAC) needs `-legacy`** when
   the consumer is `SecPKCS12Import`. Without `-legacy` the export still succeeds on the OpenSSL
   side, but `SecPKCS12Import` fails; this is worth remembering for any future encoding of real
   device identities into `.p12` for testing.

4. **`SecKeychainCreate`/`SecKeychainUnlock`/`SecKeychainDelete` are deprecated** (macOS 10.10) with
   no direct modern replacement for an ephemeral, ACL-free identity store; they are still fully
   functional on macOS 26 and are exactly the "temporary keychain, never the login keychain"
   pattern this task required. Worth flagging for whoever eventually designs the real Mac Keychain
   integration (E10-05) since the production code should not rely on deprecated API either, but
   there we control identity lifetime via the Keychain's own ACL rather than a scratch file.

5. **`.waiting`, not `.failed`, on several classes of TLS rejection seen from the client role**: no
   local client certificate against a server that requires one, and an ALPN mismatch, both surface
   to the *client's* `stateUpdateHandler` as `.waiting(POSIXErrorCode/-98xx)` rather than a terminal
   `.failed`. Network.framework appears to treat these as "might succeed on retry" rather than fatal
   — even though the *server* side reports a clean, immediate `.failed` for the same connection.
   Production impact: E01-22 / E12-18's pre-auth deadlines (TLS 10 s) must not wait for `.failed` on
   the phone side; they need an explicit deadline-cancel exactly as already specified, not an
   optimization. This spike's own listener implements exactly that pattern (§7) and it is
   confirmed necessary, not merely defensive.

6. **ALPN "no offer" vs "wrong offer" are not the same failure mode** — see §5. Only a *mismatched*
   ALPN offer is rejected by the stack; an *absent* ALPN offer is silently accepted with
   `alpn=none` negotiated. `sec_protocol_options_add_tls_application_protocol` only declares what
   the local side is willing to negotiate; it does not appear to make the extension mandatory on
   the peer.

7. **Standard TLS tooling refuses to attempt "cert without matching key."** Both `openssl s_client
   -cert/-key` and Python's `ssl.SSLContext.load_cert_chain` perform a local
   `X509_check_private_key`-equivalent check and refuse to even open a socket if the private key
   doesn't match the certificate's public key. See §10.

## Detailed evidence

All raw logs are under `spikes/e03-01-nwlistener/results/` (regenerate with
`Scripts/run-experiments.sh`; each run uses a fresh `mktemp -d` workdir and fresh identities, so
fingerprints/ports differ between runs — the pass/fail pattern does not). Section numbers below
match the driver script's section numbers.

### §1 — Baseline: correct pin, sanity, and exporter agreement (10/10)

```
$ ./Scripts/run-experiments.sh   # section 1
good-client reached ready: 10/10
exporter sha256 matches client<->server (positional pairing): 10/10
```

Sample matched pair (client log / server log, same connection):
```
client:  EVENT type=ready role=client tls_version=... alpn=tandem/1 exporter_sha256=fd4472f3a43bdde600fc8a85f1f1dba36230a8ff44dc63f20b47a8218e504248
server:  EVENT type=ready role=server remote=127.0.0.1:54349 ... exporter_sha256=fd4472f3a43bdde600fc8a85f1f1dba36230a8ff44dc63f20b47a8218e504248
```
`tls_version` prints as `tls_protocol_version_t(rawValue: 772)` = `0x0304` = TLS 1.3 on every run.

### §2 — Unpinned client certificate (verify-block rejection), 10/10

```
LOG[listener] verify_block: peer_spki=37dc9a3a70568260... match=false elapsed_us=13786.209
EVENT type=failed role=server remote=127.0.0.1:54490 error="-9808: bad certificate format"
```
`verify_block match=false` fired 10/10; `EVENT type=app-data role=server` (the marker for
"application bytes reached the listener") appeared **0 times** across all 10 attacker runs. The
listener sends a `certificate_unknown` (46) alert, confirmed independently against a matching
cert/key pair the pin store never saw:
```
$ openssl s_client -connect 127.0.0.1:4443 -tls1_3 -cert attacker-cert.pem -key attacker-key.pem -alpn tandem/1 -quiet
...ssl3_read_bytes:ssl/tls alert certificate unknown:...:SSL alert number 46
```

### §3 — No client certificate at all, 10/10 (server side)

```
EVENT type=pre-handshake-endpoint remote=127.0.0.1:54683
EVENT type=failed role=server remote=127.0.0.1:54683 error="-9808: bad certificate format" elapsed_ms=24.5
```
10/10, ~20 ms each, 0 `app-data` events. See gotcha 5 for the client-side `.waiting` behavior on
the same connections.

### §4 — TLS 1.2 rejected (openssl `-tls1_2` against the listener), 10/10

```
$ openssl s_client -connect 127.0.0.1:4504 -tls1_2 -cert good-client-cert.pem -key good-client-key.pem -alpn tandem/1
809D...:error:0A00042E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version:.../rec_layer_s3.c:918:SSL alert number 70
...
New, (NONE), Cipher is (NONE)
SSL-Session:
    Cipher    : 0000
    Master-Key:
```
`alert protocol version` (a fatal `protocol_version` alert, 70) appears in all 10 raw transcripts;
`Cipher is (NONE)` (i.e. no cipher was ever agreed) in all 10; the listener logs
`EVENT type=failed role=server` 10/10. (`Protocol: TLSv1.2` also appears in every transcript — that
line is openssl echoing the version *it requested locally*, not what was negotiated; it is present
whether or not the handshake succeeds, so it is not usable as a pass/fail marker on its own — a
mistake in the first draft of `run-experiments.sh`'s automated check, corrected to rely on the
alert text and the listener's own `failed` events instead.)

### §5 — ALPN enforcement (mismatch: 10/10 rejected; absence: 10/10 *not* rejected)

```
$ ./Scripts/run-experiments.sh   # section 5
client offering no ALPN: client-side failed/waiting=0/10; wrong-ALPN client-side failed/waiting=10/10
client offering tandem/1 negotiates tandem/1: 10/10
```
Listener-side ALPN values across the "no ALPN offered" + "wrong ALPN offered" loops (20 attempts):
```
$ grep -o "alpn=[^ ]*" listener-alpn.log | sort | uniq -c
  10 alpn=none        # client sent no ALPN extension -> accepted anyway
   0 alpn=other/1     # (never reached ready; all 10 wrong-ALPN attempts failed pre-ready)
```
This is the one **partial no-go**: D-19 says "a missing or other ALPN value fails the handshake."
"Other" (mismatched) is enforced; "missing" is not. Recommended fix (not yet implemented, since
this spike's job is to find the gap, not patch SPEC): after `.ready`, read
`sec_protocol_metadata_get_negotiated_protocol` and cancel the connection if it is `nil` or not
exactly `"tandem/1"`, before any further application data is processed. This is a one-line
application-level check, not a stack limitation that requires swift-nio-ssl.

### §6 — No session ticket / resumption artifact (10/10, both with tickets off *and* explicitly on)

```
$ ./Scripts/run-experiments.sh   # section 6
tickets=disabled: no session-ticket file ever written: 10/10 (want 10/10)
tickets=enabled (contrast case): no session-ticket file ever written: 10/10; reused-session handshakes: 0/10
```
`openssl s_client -sess_out FILE` only ever creates `FILE` if the server actually sent a
`NewSessionTicket`; across 20 total attempts (10 with `sec_protocol_options_set_tls_tickets_enabled(false)`,
10 with it explicitly `true`) no file was ever created, so no reconnect attempt could even present
a ticket. This is **stronger** evidence than the acceptance item asked for ("`-sess_out`/`-sess_in`
reconnect shows `Reused` 0/10"): here there is nothing to reuse at all. Read as: Apple's TLS 1.3
server implementation does not issue resumable tickets once client-certificate authentication is
in play, independent of the ticket-enabled flag. Matches the SPEC assumption already on file
(`E01-01` notes: "the Mac server issues no usable tickets", citing E12-03).

### §7 — Pre-handshake endpoint visibility + 10 s handshake deadline

```
EVENT type=pre-handshake-endpoint remote=127.0.0.1:54866   # printed at TCP-accept time, before connection.start()
...
EVENT type=handshake-deadline-cancel remote=127.0.0.1:xxxxx deadline_s=3.0   # nc held the socket open, sent nothing
```
`connection.endpoint` is readable immediately in `NWListener.newConnectionHandler`, before
`connection.start()` is even called — i.e. before any TLS bytes are processed. A
`DispatchWorkItem` scheduled at accept time and cancelled on `.ready` reliably force-cancels a
connection that never progresses past the TCP handshake (tested by holding a raw `nc` connection
open with no data). This directly informs E12-18's "TLS 10 s" pre-auth deadline: implement it as
an accept-time timer, not as something that depends on `.failed`/`.waiting` ever firing on its own
(see gotcha 5).

### §8 — verify_block runs before `.ready`

Structural: `sec_protocol_options_set_verify_block`'s completion handler is the API's supported
way to allow/deny the handshake — Network.framework cannot expose `.ready` before the block calls
`complete(true)` since the pin decision *is* the trust decision for this connection (no other
verification path is configured). Empirically, in every one of the 60+ runs collected here, the
`LOG[listener] verify_block: ...` line for a given connection appears immediately before that
connection's `EVENT type=ready` line, with a sub-millisecond-to-low-double-digit-millisecond gap
(`elapsed_us=902` .. `elapsed_us=23050` observed) between verify_block invocation and the `.ready`
log). No run showed a `.ready` for a connection whose verify_block had not already logged a
decision.

### §9 — Channel-binding exporter matches `openssl -keymatexport` (RFC 9266)

```
$ openssl s_client -connect 127.0.0.1:4443 -tls1_3 -cert good-client-cert.pem -key good-client-key.pem \
    -alpn tandem/1 -keymatexport "EXPORTER-Channel-Binding" -keymatexportlen 32
...
Keying material exporter:
    Label: 'EXPORTER-Channel-Binding'
    Length: 32 bytes
    Keying material: 390987BE89F498FB053754856B88070BEA540DA904715CB271EE124339856D1A

$ python3 -c "import hashlib; print(hashlib.sha256(bytes.fromhex('390987BE89F498FB053754856B88070BEA540DA904715CB271EE124339856D1A')).hexdigest())"
6aa8389b0fbc2af41756cf68c5fa88d7a64c291d7332f6f1448369df28de79fd

$ grep exporter_sha256 listener.log | tail -1
EVENT type=ready role=server remote=127.0.0.1:54440 ... exporter_sha256=6aa8389b0fbc2af41756cf68c5fa88d7a64c291d7332f6f1448369df28de79fd
```
Bit-exact match, reproduced on a second, independent run with a different key pair (server
`4dc0b9f0a05acc519d544733d1df7523e225887173b429062f768ab1643dbfb5` also confirmed against SHA-256
of the raw exporter value from a matching `s_client` invocation). Confirms E03-01's channel-binding
acceptance item (a): `sec_protocol_metadata_create_secret(metadata, "EXPORTER-Channel-Binding", 32)`
(no explicit context) is RFC 9266's `TLS-Exporter("EXPORTER-Channel-Binding", "", 32)` on
Network.framework. **Recorded outcome for E03-04: `exporter` is feasible on macOS** (Android side is
E03-03's job).

Note for `docs/spikes/channel-binding.md` (E03-04, not written by this issue): this spike only
establishes the macOS half. Per D-35, the actual channel-binding-outcome record and the go/no-go for
switching E01-01/E01-02/E70-01 to the in-band-challenge fallback belongs to E03-04, once E03-03
(Android) is also done.

### §10 — Pinned cert + mismatched private key (acceptance item b): NOT directly exercised

Attempted with both tools available in this environment:
```
$ openssl s_client -connect 127.0.0.1:4443 -tls1_3 -cert good-client-cert.pem -key attacker-client-key.pem ...
error setting private key
...x509_cmp.c:413: key values mismatch

$ python3 -c "
import ssl
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.load_cert_chain(certfile='good-client-cert.pem', keyfile='attacker-client-key.pem')
"
ssl.SSLError: [X509: KEY_VALUES_MISMATCH] key values mismatch (_ssl.c:4184)
```
Both tools validate certificate/key consistency locally (via the underlying OpenSSL/LibreSSL
`X509_check_private_key`) before opening a socket, so neither can be used to make the listener
actually process a forged `CertificateVerify`. Constructing this attack requires a non-conformant
TLS client (hand-rolled handshake, or a patched TLS library) that this spike did not have budget to
build. We record this as **not empirically exercised** rather than claim a pass.

Analytical argument for why it should still hold: TLS 1.3's `CertificateVerify` (RFC 8446 §4.4.3)
is a signature over the handshake transcript made with the certificate's private key, verified by
the *receiving* peer (here, the Mac listener) using the certificate's public key — a step performed
by the TLS stack itself, entirely independent of `sec_protocol_options_set_verify_block` (which
only ever sees the certificate, never the private key or the signature). A mismatched key produces
a transcript signature that fails that verification deterministically. Recommend: if empirical
confirmation is required before Phase 1, it should be a fuzzed/adversarial test built against a
patchable TLS client (e.g. a modified BoringSSL/OpenSSL harness) under E15-10 ("attacked by
E15-10" per the E01-01 notes), not a redo of this spike.

## Fallback recommendation

**No fallback needed.** Every acceptance item Network.framework was expected to satisfy, it did,
with one small, well-understood, application-level gap (missing-ALPN not rejected by the stack —
§5) that is cheap to close in the real implementation and does not implicate the TLS stack choice.
**E03-05 (swift-nio-ssl fallback evaluation) should record "not executed, E03-01 passed"** per its
own acceptance text.

## Files

- `spikes/e03-01-nwlistener/Package.swift` — SwiftPM package (macOS 14+, no external dependencies:
  Security/Network/CryptoKit/Foundation only).
- `spikes/e03-01-nwlistener/Sources/nwlistener-spike/`
  - `main.swift` — CLI dispatch (`setup`, `listen`, `client`, `inspect-p12`).
  - `Identity.swift` — self-signed P-256 identity generation + temporary keychain + PKCS#12 import.
  - `Pin.swift` — SPKI DER reconstruction, SHA-256 fingerprint, constant-time compare.
  - `TLSSetup.swift` — shared `NWProtocolTLS.Options` builder (min/max version, ALPN, tickets,
    resumption, verify block), RFC 9266 exporter helper.
  - `Listener.swift` — `NWListener` wrapper: accept logging, pre-handshake endpoint capture,
    handshake deadline, ready/failed/cancelled bookkeeping.
  - `Client.swift` — `NWConnection` wrapper used as the test client.
- `spikes/e03-01-nwlistener/Scripts/run-experiments.sh` — drives every experiment above end to end
  against a real `swift run` listener process and real `openssl s_client` invocations; regenerate
  `results/` by re-running it.
- `spikes/e03-01-nwlistener/results/` — raw logs + `summary.txt` from the run this document quotes.
