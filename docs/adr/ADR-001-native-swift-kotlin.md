# ADR-001: Native Swift + native Kotlin with a shared Protobuf schema

- **Status:** Accepted
- **Date:** 2026-09-24
- **Issue:** E02-02

## Context

Tandem ships an Android client and a macOS client sharing one wire protocol
(`protocol/proto/tandem/v1`). Both platforms need Keystore/Keychain-backed
identity, native TLS (`SSLSocket`/Conscrypt vs. `Network.framework`),
`MediaProjection`/`MediaCodec` vs. `VideoToolbox`, and `AccessibilityService`
— all platform-specific regardless of the source-sharing strategy chosen for
the rest of the app. The only genuinely shared surface across the two apps is
the wire protocol itself, which is already solved by Protobuf codegen
independent of the app language.

## Options

**(a) Native Swift + native Kotlin, shared Protobuf schema only**
- Pros: each platform uses its idiomatic, first-class TLS/crypto/media APIs directly; no interop layer between the shared logic and platform APIs; smaller toolchain surface (no Kotlin/Native, no Compose Multiplatform runtime); cross-platform correctness enforced by generated code + conformance vectors, which is testable independent of any shared business logic.
- Cons: business logic (framing, flow control, pairing state machine, reconnect backoff) is hand-written twice, so it can drift between platforms if not vector-tested.

**(b) Kotlin Multiplatform (KMP) sharing `core/transport`, `core/crypto`, `core/pairing`**
- Pros: one implementation of framing, flow control, and pairing state machine.
- Cons: TLS must still be platform-native on each side (Network.framework and Secure Enclave have no Kotlin/Native binding), so the KMP layer would sit above two hand-written TLS adapters anyway; Swift↔Kotlin/Native interop (cinterop, memory model, debugging) is a real ongoing cost for a shared surface this small; every third-party analytics/crash/library policy (D-31, D-32) needs separate KMP-vs-native review.

**(c) Compose Multiplatform (CMP) for shared UI**
- Pros: one UI codebase for onboarding, settings, pairing screens.
- Cons: does not touch the actual cross-platform risk (protocol/crypto/transport correctness); macOS CMP is less mature than native SwiftUI/AppKit; adds a UI toolkit dependency on top of the KMP interop cost in (b) without solving it.

## Decision

Option (a): native Swift + native Kotlin, sharing only the Protobuf schema
(`protocol/proto`) and the conformance vectors (`protocol/vectors`) that
verify both codecs agree.

Rationale: platform API dominance (Keystore/Keychain, Network.framework,
MediaProjection/MediaCodec, AccessibilityService, VideoToolbox are all
platform-specific regardless of (a) vs (b)); TLS must be platform-native on
both sides anyway; the Swift↔Kotlin/Native interop cost outweighs the value
of sharing the one surface (wire protocol) that Protobuf already solves
without KMP.

## Consequences

- Rules out shared KMP `core/*` modules — `android/core/*` and the macOS
  equivalent are independent, hand-written Kotlin and Swift.
- Cross-platform agreement (framing, message semantics, enum values) is
  enforced by `protocol/proto` codegen plus `protocol/vectors` and the E15
  conformance suite (`tools/conformance/run.sh`), not by shared source.
- Hand-duplicated logic that must stay byte-identical across platforms
  (e.g. the untrusted-string rule, D-22) needs its own vector-tested cases
  on both sides, since there is no shared implementation to fall back on.

## Revisit criteria

Reopen this ADR if either becomes true:
1. Hand-duplicated non-generated logic that must stay byte-identical across
   platforms (outside vectors-covered codecs) exceeds **2 modules**.
2. A conformance mismatch between the Android and macOS codecs recurs in
   **3 consecutive releases**.

## Links

- Backlog: E02-02 (`docs/planning/backlog/phase-0.yaml`)
- PRD: `<architecture>` → Architecture decision records to write in Phase 0 (ADR-001); Repository layout (`docs/adr/`, `protocol/vectors/`)
- Traceability: `docs/planning/traceability.md` ("Threat model + ADR-001…006 accepted" row)
