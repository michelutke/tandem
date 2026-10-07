# Tandem — UI spec

Normative description of the Tandem user interface for macOS and Android. The visual source of
truth is `ui-design.pen` (Pen app) at the repo root; PNG exports of every frame are in
[`screens/`](screens/). Where this spec and the Pen file disagree, fix one of them in the same PR.

- Scope: v1 (Phases 0–6). Extras (F-10.x) and manual pairing (F-2.2) are out of scope.
- Traceability: every screen lists the GitHub issues that implement it (§7). Design-system work is
  [#414](https://github.com/michelutke/tandem/issues/414) (Android) and
  [#415](https://github.com/michelutke/tandem/issues/415) (macOS).
- Security UX follows PRD invariants 5, 7 and 8 (§9).

---

## 1. Principles

1. **Only what matters.** Every element must answer "what is the state?" or "what can I do next?".
   Remove anything else — no decorative cards, no redundant labels, no marketing copy.
2. **One idea per screen.** A title pair states it; the rest supports it.
3. **Typography is the hierarchy.** Size and weight carry structure, not boxes or colour.
4. **Calm by default.** The app reads like a printed report, not a control room. Numbers are big
   and few; motion is slow and purposeful.
5. **Colour is a signal, never decoration.** Monochrome everywhere; green = connected / healthy /
   done; red = trust failure or destructive action. Nothing else is coloured.
6. **Native materials, shared language.** macOS uses system Liquid Glass surfaces and controls;
   Android uses Material 3 Expressive components and motion. Type, spacing, the dot motif and copy
   are identical on both.
7. **Fail closed, visibly.** Every error the transport can raise has a screen state with a single
   next step (invariant 5).

Inspiration: "Signal — Data Pipeline Monitoring" (Taras Migulko, Dribbble): monochrome Swiss
layout, period titles, dot-matrix visuals, one functional accent.

## 2. Anatomy patterns

| Pattern | Rule | Example |
|---|---|---|
| **Title pair** | Line 1 = subject + period, bold. Line 2 = state + period, regular, grey (or red for trust failure). Same size. | "Pixel 9." / "Connected." |
| **Big numeral** | One per screen at most. Unit is small, grey, bottom-aligned next to it. | `142` synced today · `43` % · `1:42` left |
| **Dot motif** | Progress, activity and status are drawn with dots: lit = ink, unlit = ink at 12 %, the current position = signal green. | Home ring, transfer progress, activity chart, QR modules |
| **Numbered rows** | Lists of actions or options are numbered `01 02 03` in mono grey, separated by hairlines. | Popover actions, permissions, facts |
| **Hairline rows** | Key/value rows separated by 1 px rules at ink 10 %. No boxes. | Devices, Settings |
| **Single primary action** | At most one filled button per screen; secondary actions are outlined or plain rows. Destructive = red fill. | "Codes match" / "They don't match" |

## 3. Tokens

### 3.1 Colour

| Token | Value | Use |
|---|---|---|
| `ink` | `#0A0A0A` | Primary text, lit dots, filled buttons |
| `ink2` | `#757575` | Secondary text, state lines, units, row numbers (≥ 4.5:1 on paper at ≥ 14 pt; use `ink` for smaller body text) |
| `line` | `#0A0A0A1A` | Hairlines, unlit dots at 12 % (`#0A0A0A1F`) |
| `paper` | `#FFFFFF` | Backgrounds (Android), glass tint base (macOS) |
| `signal` | `#00D65A` | Connected, healthy, current position, "done" |
| `alert` | `#FF3B30` | Trust failure, destructive actions, send failures |

Dark surfaces (scanner, ringing, mirror stream) invert ink/paper; `signal` and `alert` stay.
Android may map these onto a Material 3 colour scheme but must not apply dynamic colour to
`signal`/`alert`.

### 3.2 Type

Families: **Inter Tight** (UI), **JetBrains Mono** (numbers that are codes: pairing code,
fingerprints, file sizes, row numbers). Letter-spacing tightens with size.

| Role | Size / weight / tracking | Notes |
|---|---|---|
| Display numeral | 64–96 / 400 / −3 | Ring centre, pairing code, timers |
| Title pair | 30 Android, 22–28 macOS / 700 + 400 / −1 | Two lines, same size |
| Section title (Mac main window) | 26 / 700 + 400 / −0.8 | "Messages." / "3 unread." |
| Row title | 16–17 / 600 / −0.3 | |
| Body | 13–15 / 400 / 0 | Line height 1.45 |
| Meta | 11–12 / 400 / 0 | Units, timestamps, row numbers |

Platform text styles must scale: Dynamic Type sizes on macOS are not available, so honour the
system "Text size" setting where SwiftUI supports it; Android uses `sp` and must survive 200 % font
scale without clipping (titles wrap, numerals shrink to fit).

### 3.3 Spacing and shape

- 4 pt grid. Screen padding: 24 dp Android, 20–28 pt macOS glass surfaces.
- Row vertical padding 12–16. Hairline between rows, never gaps plus boxes.
- Radii: macOS popover/window 26, glass buttons full pill; Android buttons 32 (full pill), sheets
  and dialogs 32–36, M3E shapes as provided by the platform (cookie FAB, toolbar pill).

## 4. Motion

| # | Element | Behaviour | Spec |
|---|---|---|---|
| 01 | Home ring (Android) / battery dots (Mac) | Dots light up clockwise on connect; value changes animate the lit arc; the signal dot pulses once per heartbeat | Spring, low stiffness; 600 ms stagger across the arc |
| 02 | M3E switch | Thumb morphs 16 → 24 dp and shows a check when on | Material spatial spring, fast |
| 03 | Floating toolbar | Hides on scroll down, returns on scroll up; the selection pill stretches between items | M3 Expressive defaults |
| 04 | Cookie FAB | Shape-morphs cookie → circle on press, container-transforms into the send sheet | M3 Expressive defaults |
| 05 | Mac glass | System materials only; rows highlight on hover; popover uses the system open/close animation | No custom blur code |
| 06 | Find phone | Rings of dots pulse outward while ringing | 1.2 s loop |
| 07 | Pairing countdown | Timer ticks; last 10 s the numeral turns grey → red | Step, no easing |

Board: [motion and style notes](screens/motion-and-style-notes.png).

All motion is disabled or reduced when *Reduce Motion* (macOS) / *Remove animations* (Android)
is on: state changes become instant, pulses stop.

## 5. Components

### 5.1 macOS (`TandemDesign`, #415)

| Component | Description |
|---|---|
| `GlassPopover` | Menu bar extra content on system Liquid Glass; 340 pt wide; padding 20 |
| `GlassWindow` | Window with glass background and traffic lights; used for pairing and Settings |
| `GlassSidebar` | Main-window sidebar: device name + state dot, numbered sections |
| `TitleBlock` | Title pair |
| `NumberedActionRow` | `01` + label; hover background ink 5 %; optional trailing meta ("default") |
| `HairlineRow` | Key (600) left, value (ink2, mono where it is a code) right |
| `GlassToggle` | System toggle, tinted ink |
| `PillButton` | Primary (ink / alert fill) and secondary (ink 5 %) |
| `DotProgress`, `DotRing`, `DotQR` | Dot visuals; DotQR renders modules as dots with rounded finder patterns and a ≥ 4-module quiet zone |
| `GlassSheet` | Modal confirmation on a 20 % scrim |

### 5.2 Android (`core/designsystem`, #414)

| Component | Description |
|---|---|
| `TandemScaffold` | Status bar, title pair, content, M3E floating toolbar + cookie FAB |
| `TitleBlock`, `NumberedRow`, `HairlineRule` | As on macOS |
| `M3ESwitch` | Material 3 Expressive switch; ink track, signal thumb with check when on |
| `FloatingToolbar` | Home, Notifications, Activity, Settings; selected item on a white pill |
| `CookieFab` | Share/send FAB, signal fill |
| `PillButton` | Full-width primary (ink or alert) / outlined secondary |
| `TandemBottomSheet`, `TandemDialog` | M3E sheet and bottom-anchored dialog (radius 32–36) |
| `Banner` | Alert-tinted inline banner with one action ("Fix") |
| `DotRing`, `DotChart`, `DotHero` | Dot visuals with TalkBack descriptions |
| `ControlIndicator` | Accessibility-overlay pill "Mac is controlling · Stop" (invariant 8) |

## 6. Home ring (Android)

Decision (D-55): **idle shows items synced today; while a task runs the ring shows that task.**

| Ring state | Numeral | Label | Dots |
|---|---|---|---|
| Idle | count of items synced today (notifications, clips, files) | "synced today" | lit = today vs. 7-day average, capped at full |
| Live task: transfer | percent | file name → Mac / from Mac | lit = progress |
| Live task: mirroring | mm:ss | "mirroring" | full, signal dot moves once per second |
| Live task: ringing | — | "ringing" | pulse (motion 06) |
| Reconnecting | seconds to next attempt | "next try · attempt N" | all unlit |

Alternatives considered ([Home ring options](screens/home-ring-options.png)): link uptime, key age. Mac battery was dropped.

## 7. Screens

Each row: screen, PNG, states covered, implementing issues.

### 7.1 macOS

**Menu bar popover** — the primary surface.

| Screen | PNG | States / content | Issues |
|---|---|---|---|
| Connected | [png](screens/mac-popover-connected.png) | "Pixel 9." / "Connected."; phone battery numeral + dot gauge; actions 01 Send file, 02 Push clipboard, 03 Find phone, 04 Mirror screen, 05 Messages; Open Tandem; Settings, Quit | #223 #224 #236 #266 #279 #357 |
| Offline | [png](screens/mac-popover-offline.png) | "Offline."; last seen + network; 01 Retry now | #229 #223 |
| Ringing | [png](screens/mac-popover-ringing.png) | "Ringing."; 01 Stop ringing | #236 |
| Trust error | [png](screens/mac-popover-trust-error.png) | "Key changed." (red); explanation; 01 Pair again, 02 Unpair | #159 #228 |
| Update needed | [png](screens/mac-popover-update-needed.png) | "Update needed." (red); protocol versions; 01 Check for update | #159 #228 |
| Not paired | [png](screens/mac-popover-not-paired.png) | "Tandem." / "No phone yet."; 01 Pair phone | #223 #188 |

**Pairing window**

| Screen | PNG | States / content | Issues |
|---|---|---|---|
| QR | [png](screens/mac-pairing-qr.png) | "Pair." / "Scan with your phone."; dot QR; `1:42` left; 3 tries dots; hidden from screen capture | #188 #179 |
| Confirm | [png](screens/mac-pairing-confirm.png) | "Pixel 9." / "Same code on both?"; `482 913`; 01 Don't pair (**default**), 02 Pair | #185 |
| Expired | [png](screens/mac-pairing-expired.png) | "Code expired."; `0:00`; 01 New code, 02 Cancel | #179 #188 |
| No tries left | [png](screens/mac-pairing-no-tries-left.png) | "Too many tries." (red); `0/3`; New code, Cancel | #186 #188 |
| Paired | [png](screens/mac-pairing-paired.png) | "Paired." / "Pixel 9 is ready."; signal dot; Done | #185 |

**Main window** (glass sidebar: Messages, Photos, Calls, Transfers, Devices — #419)

| Screen | PNG | States / content | Issues |
|---|---|---|---|
| Messages | [png](screens/mac-main-messages.png) | Threads ("Messages." / "3 unread."), search, conversation, composer with SIM | #311 #312 #309 |
| Messages · Send failed | [png](screens/mac-main-messages-send-failed.png) | Bubble meta "Not sent · no service · Retry" (red) | #312 |
| Messages · Offline | [png](screens/mac-main-messages-offline.png) | Sidebar "Offline · seen 14:02"; composer "Sends when Pixel 9 is back" | #419 |
| Messages · Off | [png](screens/mac-main-messages-off.png) | "Turned off on the phone." | #419 |
| Photos | [png](screens/mac-main-photos.png) | "Photos." / "4,812 on phone."; grid; multi-select; Download N | #298 #303 |
| Photos · No access | [png](screens/mac-main-photos-no-access.png) | "Pixel 9 hasn't shared photos." | #419 #298 |
| Calls | [png](screens/mac-main-calls.png) | In call (name, `04:12`, Hang up); search + call contacts | #334 #333 |
| Transfers | [png](screens/mac-main-transfers.png) | Active transfer (`43` %, dot progress, speed); earlier list | #292 |
| Devices | [png](screens/mac-main-devices.png) | Name, status, paired date, phone key, this Mac's key; Rotate key, Revoke | #191 #382 |
| Revoke confirm | [png](screens/mac-main-revoke-confirm.png) | Glass sheet "Revoke Pixel 9?"; Cancel / Revoke (red) | #190 #191 |

**Other windows and system surfaces**

| Screen | PNG | States / content | Issues |
|---|---|---|---|
| Mirror window | [png](screens/mac-mirror-window.png) | Stream; glass toolbar Back, Home, Recents, "Control on", Stop | #352 #368 |
| Mirror · Waiting | [png](screens/mac-mirror-waiting.png) | "Waiting." / "Accept on Pixel 9 to start."; Cancel | #357 |
| Mirror · Declined | [png](screens/mac-mirror-declined.png) | "Declined." / "Nothing was shared."; Close | #357 |
| Settings | [png](screens/mac-settings.png) | Tabs General, Notifications, Files, Privacy; toggles; download folder | #227 #174 |
| Notifications | [png](screens/mac-notifications.png) | Phone notification with inline reply; incoming call Decline / Answer; file received | #254 #333 #292 |
| Notifications · Edge | [png](screens/mac-notifications-edge.png) | File offer Accept / Decline (auto-accept off); transfer failed + Retry; key changed (trusted rotation) | #287 #292 #376 |

### 7.2 Android

| Screen | PNG | States / content | Issues |
|---|---|---|---|
| Onboarding · Welcome | [png](screens/android-onboarding-welcome.png) | Dot hero; "Tandem." / "Your phone, on your Mac. Privately."; Get started | #214 |
| Onboarding · Permissions | [png](screens/android-onboarding-permissions.png) | 01 Notifications, 02 Battery, 03 Camera, 04 SMS & calls (Skip); each with one-line reason | #214 #204 |
| Scan | [png](screens/android-pairing-scan.png) | Dark; "Scan." / "The code on your Mac."; viewfinder; "Decoded on this phone." | #187 |
| Scan · Invalid code | [png](screens/android-scan-invalid-code.png) | Red viewfinder; "Not a Tandem code." / "Or it was already used." | #196 |
| Scan · Mac unreachable | [png](screens/android-scan-mac-unreachable.png) | "Can't reach the Mac." / "Same Wi-Fi?"; client-isolation hint | #196 |
| Confirm | [png](screens/android-pairing-confirm.png) | "MacBook Pro." / "Same code on both?"; `482` `913`; Codes match / They don't match | #182 |
| Pairing · Declined | [png](screens/android-pairing-declined.png) | "Declined." / "The Mac said no." (red); Scan again | #196 |
| Pairing · Paired | [png](screens/android-pairing-paired.png) | "Paired."; dot mark; Done | #182 |
| Home | [png](screens/android-home.png) | "Tandem." / "Linked to MacBook Pro."; ring (§6); 01–04 feature switches; toolbar + FAB | #416 #209 |
| Home · Live task | [png](screens/android-home-live-task.png) | "Sending 1 file."; ring = `43` % | #416 #281 |
| Home · Reconnecting | [png](screens/android-home-reconnecting.png) | "Reconnecting…"; grey dots; `3` s next try | #416 #206 |
| Home · Battery restricted | [png](screens/android-home-battery-restricted.png) | Red banner "Battery restricted." + Fix | #204 |
| Activity | [png](screens/android-activity.png) | "Activity." / "Last 7 days."; dot chart; metadata-only list | #417 |
| Notification apps | [png](screens/android-notification-apps.png) | "24 of 31 apps."; numbered apps with M3E switches | #241 |
| Notifications · Access off | [png](screens/android-notifications-access-off.png) | "Access off." (red); Allow access | #239 |
| Settings | [png](screens/android-settings.png) | Paired Mac, Battery, Key (Rotate), Unpair (red) | #418 |
| Unpair confirm | [png](screens/android-unpair-confirm.png) | M3E dialog; Unpair (red) / Cancel | #189 |
| Rotate key | [png](screens/android-rotate-key.png) | M3E dialog; Rotate / Cancel | #377 |
| Send to Mac | [png](screens/android-send-to-mac.png) | Share-sheet target: bottom sheet with items, destination, Send | #280 #261 |
| Incoming file | [png](screens/android-incoming-file.png) | "From Mac." / name · size; Save to; Accept / Decline | #276 |
| Quick Settings tile | [png](screens/android-quick-settings-tile.png) | "Send clip" tile (signal when available), "Mirror" tile | #267 |
| Mirror request | [png](screens/android-mirror-request.png) | "Mirror." / "MacBook Pro wants to see your screen."; 3 facts; Start mirroring / Not now | #361 |
| Mirror · System consent | [png](screens/android-mirror-system-consent.png) | System MediaProjection dialog (not styled by Tandem) | #347 |
| Remote control opt-in | [png](screens/android-remote-control-opt-in.png) | "Control." / "Let your Mac tap and type."; Open Accessibility settings / View only | #363 |
| Mirroring active | [png](screens/android-mirroring-active.png) | Overlay pill "Mac is controlling · Stop" above any app | #367 |
| Find phone ringing | [png](screens/android-find-phone-ringing.png) | Dark; "Ringing." / "From MacBook Pro."; pulsing dots; Found it | #234 #235 |
| Trust error | [png](screens/android-trust-error.png) | "Blocked." / "The Mac's key changed." (red); Pair again / Unpair | #160 |

## 8. Connection state matrix

Which screen state each transport state maps to. Implemented by the state machines (#157, #158)
and surfaced by #159, #160, #228, #416.

| Transport state | Mac popover | Mac main window | Android home |
|---|---|---|---|
| Not paired | Not paired | — (opens pairing) | Onboarding |
| Pairing window open | Pairing · QR / Confirm | — | Scan / Confirm |
| Connecting / reconnecting | Offline (last seen) | Sidebar "Offline · seen …" | Reconnecting |
| Connected | Connected | Sections live | Home (ring §6) |
| Pin mismatch / unknown peer | Trust error | Trust error banner, sections disabled | Trust error |
| Version mismatch | Update needed | Update needed | Trust error variant "Update needed." |
| Revoked by peer | Not paired + "Pixel 9 unpaired this Mac" | — | Onboarding + "MacBook Pro removed this phone" |

## 9. Security UX rules

1. **Default to safety.** In the pairing confirm, "Don't pair" is the default button; the phone
   pins the Mac only after "Codes match" (AC-20).
2. **Codes are shown big and mono.** Six digits in two groups of three; never truncate.
3. **Trust failures are red, stop everything, and offer one action.** No "continue anyway".
4. **Never show content where it isn't needed.** The Android activity feed stores metadata only
   (#417). Mac notifications hide text while the Mac is locked when the setting is on.
5. **Remote control is always visible.** The "Mac is controlling · Stop" pill is drawn by the
   accessibility overlay above all apps whenever input is accepted (invariant 8, #367).
6. **Pairing QR window is excluded from screen capture** and shows the countdown and remaining
   tries at all times.
7. **Peer-provided strings are sanitised** before display (device names, file names — #198, #199).

## 10. Copy

Voice: short, calm, factual. Sentences end with a period. No exclamation marks, no "Oops".
Titles are nouns or states, not questions — except confirmations ("Revoke Pixel 9?").

| Key | Text |
|---|---|
| state.connected | Connected. |
| state.offline | Offline. |
| state.reconnecting | Reconnecting… |
| state.keyChanged | Key changed. |
| state.blocked | Blocked. |
| state.updateNeeded | Update needed. |
| pair.scan | Scan with your phone. |
| pair.confirm | Same code on both? |
| pair.expired | Code expired. |
| pair.tooManyTries | Too many tries. |
| pair.declined | The Mac said no. |
| pair.paired | {device} is ready. |
| scan.invalid | Not a Tandem code. / Or it was already used. |
| scan.unreachable | Can't reach the Mac. / Same Wi-Fi? |
| scan.pinMismatch | Not trusted. / This Mac's identity changed. Pair again. |
| scan.identityUnavailable | Not paired. / This phone's key couldn't be created. |
| mirror.request | {mac} wants to see your screen. |
| mirror.waiting | Accept on {phone} to start. |
| mirror.declined | Nothing was shared. |
| control.pill | Mac is controlling |
| call.place | Call |
| call.dialing | Calling. |
| call.needsPhoneTap | Tap the notification on your phone. |
| call.failed | Couldn't call. |
| home.ring.idle | synced today |
| notif.accessOff | Access off. |
| battery.restricted | Battery restricted. / Android may cut the link overnight. |
| send.clipboard.sent | Sent to Mac. (Android toast) / Sent to phone. (Mac menu) |
| send.clipboard.received | Received from Mac. (Android toast) / Received from phone. (Mac menu) |
| send.clipboard.empty | Nothing on the clipboard to send. |
| send.clipboard.tooLarge | Text too large to send (max 1 MiB). (Android) / Clipboard too large to send, use file transfer (Mac) |
| settings.clipboard.autoCapture | Send copies to Mac automatically (Android Settings row; off by default) |
| settings.clipboard.autoCapture.explain | Tandem needs its Accessibility service to notice when you copy. Accessibility can see everything on screen, not just the clipboard. Tandem only watches the system copy notice and reads nothing else. Turn on Tandem clipboard in the next screen. You can switch this off any time. |
| settings.clipboard.autoCapture.needsService | Allow Tandem in Accessibility settings. |
| send.clipboard.protected | Not sent: protected item (Mac menu) |
| send.file.started | Sending to Mac… (Android toast) / Sending to phone. (Mac menu) |
| send.file.sent | Sent to Mac. (Android toast) |
| send.file.rejected | Mac declined the file. (Android toast) |
| send.file.failed | Couldn't send the file. (Android toast) |
| files.saveTo | Save files to |
| files.choose | Choose… |
| files.reset | Reset |
| files.folderFailed | Couldn't use that folder. |
| send.notConnected | Not connected to your Mac. (Android) / Phone not connected. (Mac menu) |
| send.file.folder | Folders can't be sent. (Mac menu) |
| file.incoming | Incoming file / {name} ({size}) with Accept and Decline: notification and, on Mac, an in-app alert |

## 11. Accessibility

- Contrast: text ≥ 4.5:1 (use `ink` instead of `ink2` below 14 pt); dots are decorative when a
  numeral is present, otherwise they carry a VoiceOver/TalkBack value.
- Colour is never the only signal: every green/red state has text ("Connected.", "Key changed.").
- Hit targets ≥ 44 pt (macOS toolbar) / 48 dp (Android).
- Screen readers: title pairs are read as one heading ("Pixel 9, connected").
- Reduce Motion / Remove animations and Reduce Transparency are honoured (§4, #414, #415).

## 12. Resolved design questions

- Mac popover hero shows phone battery (D-56); Android home uses the synced-today ring (D-55).
- Wi-Fi signal strength is not shown; only network type and cellular level (D-51).
- Mac notification text uses the system banner; custom glass styling applies only to Tandem's own
  windows.
