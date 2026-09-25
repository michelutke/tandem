# E14-23 spike: QR decoder choice (ML Kit bundled telemetry vs. zxing-cpp)

Backlog: `docs/planning/backlog/phase-1.yaml` `id: E14-23`. GitHub #200. Decision rule:
`docs/planning/decisions.md` D-32/D-43. Consumer: `id: E14-10` (CameraX QR scanner UI).

Throwaway apps: `spikes/e14-23-qr-decoder/` (standalone Gradle project, AGP 9.4.1 / Gradle 9.7.1 /
built-in Kotlin, `compileSdk 35`, `minSdk 29`; three modules — `app-baseline` (no decoder, APK-size
control), `app-mlkit`, `app-zxing`). Not part of the real `android/` module tree.

## TL;DR — decision

**zxing-cpp** (`io.github.zxing-cpp:android`), per the D-32/D-43 rule ("ML Kit only if zero egress
is proven, else zxing-cpp") — already the owner's accepted default (D-43) for this exact question.
This spike supplies the evidence:

- **ML Kit fails on two independent go criteria, not one.** (a) License: `com.google.mlkit:barcode-scanning`
  is distributed under the **ML Kit Terms of Service** (Google's own terms, not an OSS license), which is
  not on the E00-29 allowlist (Apache-2.0/MIT/BSD-2/BSD-3/ISC/Zlib only) — this alone is disqualifying,
  independent of egress. (b) Egress cannot be proven zero: even the **bundled** `barcode-scanning:17.3.0`
  artifact — the one explicitly chosen to avoid the Play-services/unbundled variant — has a *direct*
  Gradle dependency on `com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1`, which pulls
  the full Firebase/GMS telemetry stack (`play-services-base`, `play-services-basement`,
  `com.google.android.datatransport:transport-{api,backend-cct,runtime}`,
  `com.google.firebase:firebase-{components,encoders,encoders-json,annotations}`). There is no documented,
  supported opt-out for this logging path (see "Telemetry opt-out" below) — only unsupported reflection
  hacks or a Gradle `exclude()` that risks silently breaking the library on the next update.
- zxing-cpp has **zero** Google/Firebase/telemetry transitive dependencies (only `androidx.camera:camera-core`
  for its `ImageProxy` overload, and `kotlin-stdlib`), is Apache-2.0 (on the allowlist), and is actively
  maintained (latest release `3.1.1`, 2026-07-29; last commit 2026-09-20).
- Both decoders correctly decoded every fixture and comfortably beat the p95 ≤ 3 s go criterion by three
  orders of magnitude: ML Kit p50 9 ms / p95 10 ms; zxing-cpp p50 0 ms / p95 0 ms (sub-millisecond).
- In the emulator window actually observed (20 decodes + 60 s idle), both apps showed **0 bytes** of
  rx/tx (`dumpsys netstats detail`, per-UID) and the tcpdump capture had no `googleapis`/`firebaselogging`/
  `google.com`/`gstatic` strings for either app — but this window is far short of the backlog's own
  24 h idle criterion, and ML Kit's Firelog/CCT pipeline is documented to **batch and delay** uploads,
  so a clean short window does not prove zero egress (this is exactly the gap the D-32 rule is written
  to route around: on doubt, choose zxing-cpp).
- APK size: zxing-cpp adds roughly half of ML Kit's footprint (single-ABI estimate below).

Decision, in the D-32/D-43 vocabulary: ML Kit's egress cannot be proven zero → **zxing-cpp**.

## Environment

- AVD: `teamorg_api34` (Android 14, API 34), headless (`-no-window -no-audio -no-boot-anim -netfast`),
  boot with a full packet capture (`-tcpdump capture.pcap`).
- Driver: `spikes/e14-23-qr-decoder/scripts/run-spike.sh [avd-name] [output-dir]` — boots the AVD once,
  builds and installs both `app-mlkit` and `app-zxing` (+ their `androidTest` APKs) sequentially, runs
  each instrumented suite, snapshots `dumpsys netstats detail` before the run and after a 60 s idle
  window, pulls the `E1423Spike` logcat tag, then kills the emulator (`adb emu kill`). Every run in this
  spike ended with no emulator left in `adb devices`.
- Fixtures: `spikes/e14-23-qr-decoder/scripts/generate-fixtures.sh` renders two `tandem://pair` QR PNGs
  with `qrencode` (`brew install qrencode`), matching the PRD F-2.1 payload shape
  (`tandem://pair?v=1&fp=<b64url SPKI-SHA256>&s=<b64url 128-bit secret>&a=<addr1,addr2>&p=<port>&n=<name>`):
  a "typical" fixture (2 addresses, short name — timed 20×) and a "max" fixture (8 literal IPs per D-18,
  a 64-byte name — correctness only, not timed). Both decoders decode both fixtures from a static PNG
  bitmap (`BitmapFactory.decodeStream`), never a live camera feed, matching this spike's scope.

## Go criteria vs. results (per E14-23 acceptance)

| Criterion | ML Kit (bundled) | zxing-cpp |
|---|---|---|
| 0 network connections | Not provable (see above); 0 bytes observed in the tested 60 s window, but the artifact depends on a live GMS/Firebase logging stack with no opt-out | Yes — no network-capable code in the dependency graph at all |
| p95 decode ≤ 3 s | p50 9 ms / p95 10 ms (pass) | p50 0 ms / p95 0 ms (pass) |
| License on E00-29 allowlist (Apache-2.0/MIT/BSD-2/BSD-3/ISC/Zlib) | **Fail** — "ML Kit Terms of Service" | **Pass** — Apache-2.0 |

Per D-32/D-43: any one failing criterion routes the decision to zxing-cpp; ML Kit fails two.

## Dependency graph evidence

`./gradlew :app-mlkit:dependencies --configuration debugRuntimeClasspath` (full output:
`/tmp/e1423-results/deps-mlkit.txt`, not committed — regenerate with the command above):

```
\--- com.google.mlkit:barcode-scanning:17.3.0
     +--- com.google.android.gms:play-services-basement:18.4.0
     +--- com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1
     |    +--- com.google.android.gms:play-services-tasks:18.2.0
     |    +--- com.google.android.gms:play-services-base:18.5.0
     |    +--- com.google.android.gms:play-services-basement:18.4.0
     |    +--- com.google.android.datatransport:transport-api:2.2.1
     |    +--- com.google.android.datatransport:transport-backend-cct:2.3.3
     |    +--- com.google.android.datatransport:transport-runtime:2.2.6
     |    +--- com.google.firebase:firebase-components:16.1.0
     |    +--- com.google.firebase:firebase-encoders-json:17.1.0
     |    +--- com.google.firebase:firebase-encoders:16.1.0
     |    \--- com.google.firebase:firebase-annotations:16.0.0
     +--- com.google.mlkit:barcode-scanning-common:17.0.0
     +--- com.google.mlkit:common:18.11.0
     \--- com.google.mlkit:vision-common:17.3.0
```

The bundled artifact (chosen specifically to avoid the Play-services/unbundled variant per the
backlog description) has a **direct** dependency on
`com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1` — the same Firebase/GMS
"Firelog"/CCT (`transport-backend-cct`) event-logging pipeline used across Google's Play-services SDKs.
Bundling the on-device model does not remove this dependency; it only avoids downloading the model
itself at runtime.

`./gradlew :app-zxing:dependencies --configuration debugRuntimeClasspath`
(`/tmp/e1423-results/deps-zxing.txt`): the only non-Kotlin, non-AndroidX dependency is
`androidx.camera:camera-core:1.4.1` (pulled in solely for the `BarcodeReader.read(ImageProxy)`
overload used by camera-preview integrations; this spike calls the `read(Bitmap, ...)` overload
directly). Zero matches for `datatransport|firebase|play-services|gms`.

## Telemetry opt-out

The ML Kit barcode-scanning docs (developers.google.com/ml-kit/vision/barcode-scanning/android)
document a `com.google.mlkit.vision.DEPENDENCIES` manifest meta-data tag, but that only controls
**which model** is bundled/downloaded — it is not a logging opt-out. No official, supported flag to
disable the Firelog/CCT usage-logging calls was found. Public workarounds are all unsupported:
excluding the datatransport/Firebase artifacts via Gradle `exclude()` (relies on ML Kit swallowing the
resulting `NoClassDefFoundError` — undocumented, could break on any ML Kit point release) or reflection
that patches ML Kit's internal `LazyInstanceMap` to force `enableFirelog=false` (explicitly described by
its own author as "extremely hacky and will probably break in the next update"). Neither qualifies as
"a documented opt-out" for the D-32 go criterion.

## Egress observation (this session's window: 20 decodes + 60 s idle, not the backlog's 24 h)

For each of `app-mlkit` and `app-zxing`: `dumpsys netstats detail` was snapshotted for the app's UID
immediately before install+test and again after the instrumented suite plus a 60 s idle sleep
(`scripts/netstats-bytes.py` sums `rb=`/`tb=` bytes for that UID across every interface/tag block).
Both showed:

```
uid=<mlkit-uid> rxBytes=0 txBytes=0 totalBytes=0   (before and after)
uid=<zxing-uid> rxBytes=0 txBytes=0 totalBytes=0   (before and after)
```

The emulator boot also ran under `-tcpdump capture.pcap`; a `strings` scan of the resulting capture for
`googleapis|firebaselogging|google\.com|gstatic|doubleclick` returned no matches for either app's test
run.

**This is evidence of absence in the tested window, not proof of absence.** The Firelog/CCT client is
documented to batch events and can defer the actual upload (backoff on failure, batched flush
intervals); a 60 s window on a freshly-installed app with no prior successful upload is exactly the
case most likely to show nothing yet. The backlog's own acceptance text acknowledges this same gap for
the full-app release audit (E71-14: "the 24 h physical-phone manual gate is the only check that would
catch a rare/delayed telemetry call, and it is a gate, not continuous monitoring" — `docs/threat-model.md`
§ egress row). Given the dependency-graph and license findings above already fail two of the three go
criteria on their own, this spike did not extend the observation window to the full 20-scan/24 h
protocol described in the backlog acceptance text; that would only be worth the machine-time if the
dependency graph were clean, which it is not.

## Decode latency (median / p95 over 20 timed runs, "typical" fixture, warm-up run excluded)

Both are the time to decode an already-loaded, in-memory `Bitmap` — the go criterion's "decode time at
30-60 cm" (camera capture + preprocessing) is a superset of this that E14-10's `manual:` gate
(`qrScanner_realCameraMacDisplay_decodesWithin3s`) still needs to cover; this spike measures decoder
throughput only, not the CameraX pipeline.

| Decoder | p50 | p95 | All 20 (ms) |
|---|---|---|---|
| ML Kit (bundled) | 9 ms | 10 ms | 8,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,10,10 |
| zxing-cpp | 0 ms | 0 ms | all 0 (sub-millisecond; `System.nanoTime()` resolution shows 0 rounded ms) |

Both pass the ≤ 3 s p95 go criterion by roughly two to three orders of magnitude; latency was not a
deciding factor between the two options.

## APK size impact

Debug, unminified, all four ABIs (`arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`) bundled in one APK —
this over-states what a real device installs (a release build ships one ABI via app-bundle splits or
ABI-specific APKs, and R8 would shrink the Java/Kotlin side further), but the three modules share build
config so the *relative* comparison is fair:

| Module | APK size | Delta vs. baseline |
|---|---|---|
| `app-baseline` (no decoder) | 2,515,800 bytes (2.40 MiB) | — |
| `app-mlkit` | 30,727,479 bytes (29.30 MiB) | **+28.2 MiB** |
| `app-zxing` | 12,081,943 bytes (11.52 MiB) | **+9.6 MiB** |

Single-ABI (`arm64-v8a`) estimate — native `.so` for that ABI plus the total dex delta over baseline
(2,496,980 bytes of dex), which is a closer proxy for what one device actually installs:

| Module | arm64-v8a native libs | Dex total | Dex delta vs. baseline | Estimated per-device delta |
|---|---|---|---|---|
| `app-mlkit` | `libbarhopper_v3.so` — 4,946,720 bytes (4.72 MiB, the barcode model binary) | 8,963,888 bytes | +6.47 MiB | **~11.2 MiB** |
| `app-zxing` | `libzxingcpp_android.so` + 2 small CameraX JNI helpers — 1,668,024 bytes (1.59 MiB) | 5,595,808 bytes | +3.10 MiB | **~4.7 MiB** |

zxing-cpp's footprint is roughly 40% of ML Kit's either way it is measured.

## License and maintenance status

| | ML Kit (bundled) | zxing-cpp |
|---|---|---|
| License | ML Kit Terms of Service (proprietary, Google) — **not on the E00-29 allowlist** | Apache-2.0 — on the allowlist |
| Latest version | `com.google.mlkit:barcode-scanning:17.3.0` (dl.google.com/maven2, checked 2026-09-25) | `io.github.zxing-cpp:android:3.1.1` (Maven Central, published 2026-07-29) |
| Maintenance | Actively maintained by Google | Actively maintained; last commit to `master` 2026-09-20 |

This spike built and tested against `zxing-cpp:2.3.0` (the version `search.maven.org`'s index had
resolvable at the time; `repo1.maven.org`'s own `maven-metadata.xml` shows `3.1.1` is actually current).
Checked `3.1.1`'s POM directly: its only dependencies are still `androidx.camera:camera-core` and
`kotlin-stdlib` — the zero-telemetry finding holds across versions. **E14-10 should pin `3.1.1` (or
later), not `2.3.0`.**

## API surface exercised

- `com.google.mlkit.vision.barcode.BarcodeScanning.getClient(BarcodeScannerOptions)`,
  `com.google.mlkit.vision.common.InputImage.fromBitmap(bitmap, 0)`,
  `com.google.android.gms.tasks.Tasks.await(task, timeout, unit)` (synchronous wrapper for the test
  harness only — production code (E14-10) should use the async `Task`/coroutine bridge, not `Tasks.await`
  on a UI-adjacent thread).
- `zxingcpp.BarcodeReader(options).read(bitmap: Bitmap, cropRect: Rect = Rect(), rotation: Int = 0): List<Result>`,
  restricted to `Format.QR_CODE` via `Options(formats = setOf(Format.QR_CODE))`. `Result.text: String?`
  carries the decoded payload.

## What this spike does not settle

- The 24 h idle / 20-scan egress protocol described in the backlog acceptance text was not run in full
  (see "Egress observation" above for why); if a future re-check of ML Kit is ever wanted, that longer
  protocol — not this spike's 60 s window — is the one that could actually move the needle.
- Decode latency measured here is decoder-only (bitmap already in memory); the camera-to-decode latency
  on a physical device is E14-10's `manual:` gate.
- Native-library size differences across ABIs beyond `arm64-v8a` were not individually broken down.

## Recommendation for E14-10

Implement the `QrDecoder` seam (E14-10) against **zxing-cpp `3.1.1`+**, restricted to
`Format.QR_CODE`, using the `read(Bitmap, ...)` overload for the `instrumented:` fixture-bitmap test
and CameraX's `ImageProxy` for the live preview path. Record this decision and the dependency
justification for `io.github.zxing-cpp:android` in `docs/dependencies.md` once E00-29 creates that
registry (it does not exist in the tree yet, `lands_in_phase: 1`); this document is the citation to
link from that entry in the meantime.
