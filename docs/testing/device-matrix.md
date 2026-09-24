# Physical device matrix

Devices `manual:` gates (`docs/testing/manual-gates.md`, tracked by E00-23) run on. The owner
currently has one Android phone and one or more Apple-silicon Macs; rows below marked **needed**
are gaps to close before the gates that require them can be signed off. A device satisfies a row
once its model, OS version, security level and OEM skin are recorded here.

## Android

| Class | Model (target) | Android version | Security level | OEM skin | Status | Needed for |
|---|---|---|---|---|---|---|
| StrongBox Pixel | Google Pixel, 6-series or newer (Titan M2) | current stable | StrongBox — confirm via `KeyInfo.securityLevel` | AOSP (Pixel) | needed unless owner's phone already is one | E10-01, E14-18 StrongBox rows |
| TEE-only mid-range | Budget/mid-range device with no discrete secure element (e.g. Motorola Moto G-series) | current stable | TEE — confirm StrongBox HAL absent | near-stock | needed | E10-01, E14-18 TEE-only rows |
| API 29 minimum | Any phone whose last OTA is Android 10, e.g. a 2019-era device that never updated past it | 10 (API 29) | record actual | record actual | needed | E14-18 API 29 row |
| Samsung (One UI) | Samsung Galaxy A- or S-series | current for the model | TEE (Knox) — confirm via `KeyInfo` | One UI | needed | E14-18 Samsung row, E20-04 OEM guidance, E20-02 battery-killer |
| Aggressive-battery OEM | Xiaomi Redmi/Poco (MIUI/HyperOS) or OnePlus (OxygenOS) | current for the model | TEE | MIUI/HyperOS or OxygenOS | needed | E20-04 OEM guidance, E20-02 battery-killer |
| Daily-driver phone | Owner's current Android phone | current stable, ≥ 13 for E31-05 | record actual | record actual | owned | all other Android `manual:` rows (connectivity, notifications, clipboard, mirroring, SMS, calls, contacts — most need a real SIM/carrier and everyday accounts) |

Version-specific note: E31-05's `sensitiveClip_android13Device_*` needs Android 13+; use the
daily-driver phone if it already meets that, otherwise a second device.

## macOS

| Class | Model | macOS version | Notes |
|---|---|---|---|
| Apple silicon — macOS 15 | _owner's Mac(s)_ | 15 (Sequoia) baseline | Required baseline for every Mac-side `manual:` row (E21-02, E21-03, E22-03, E22-04, E23-08, E30-07, E30-15, E30-17, E40-21, E40-22, and the cross-device rows). |
| Apple silicon — latest macOS | _owner's Mac(s), or a second Mac/OS beta partition_ | latest shipping release | Forward-compatibility pass of the same rows once the baseline passes. |

## Recording a device

When a device is acquired or swapped in, fill in its row above (model, version, security level,
OEM skin, status) — do not add a new table. `KeyInfo.securityLevel` (Android) is the source of
truth for StrongBox vs. TEE; do not infer it from the marketing spec.
