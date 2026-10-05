# Manual test gates

Physical-device sign-off log for every `manual:` tdd entry in `docs/planning/backlog/*.yaml`
(see `docs/planning/README.md` → Test layers). Devices are listed in `docs/testing/device-matrix.md`.

Scaffolded and checked by `ruby tools/planning/manual_gates.rb` (see header of that file for
usage). The generator only appends missing headings below — it never edits or deletes one, so
filled-in procedures and sign-off rows are safe. A phase exits only when every P0 `manual:` row
for that phase is signed off.

### canaryProcedure_livePhoneMacPairingWithCanaryName_zeroOccurrencesInCapture (E15-07, phase 1)

[tools] Canary procedure script (clipboard, file, notification, mirror injection)

Reference — E15-07 acceptance criteria:
- Two consecutive runs generate two distinct canaries (no reuse; suffix has 128 random bits).
- The Phase 1 run injects the canary only through PairRequest.deviceInfo.displayName during a real pairing (no test-only message type exists).
- `grep` over `protocol/proto/**` for message names containing Debug, Echo or Test returns 0 matches (CI check).
- Each later-phase step is enabled by a flag naming the owning feature issue; once that issue is marked done, running with the step disabled exits non-zero (fails, not skips).
- The notification step's dry-run output contains the companion broadcast with kind `canary` and the generated nonce.
- The automated Phase 1 run (JVM harness + real Mac app) and the live phone+Mac run both end with 0 canary occurrences in the capture and exit 0; later phases extend the live run (E61-09 mirror, E71-07 all steps).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### nmapPhoneCheck_pairedPhysicalPhone_zeroOpenTcpPorts (E15-12, phase 1)

[tools] nmap phone-listener check script

Reference — E15-12 acceptance criteria:
- On fixture XML with an open non-allowlisted port the script exits 1 and lists the port(s).
- On fixture XML with only allowlisted ports open the script exits 0.
- On fixture XML reporting the host down/unreachable the script exits non-zero (never passes).
- The Tandem app uid owns 0 listening TCP sockets and 0 bound UDP sockets on the emulator after the connection manager starts.
- Manual gate — `nmap -p-` (65535 TCP ports) against a paired physical phone reports 0 open non-allowlisted ports.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### androidKeyStoreIdentity_strongBoxDevice_keyInfoSecurityLevelStrongBox (E10-01, phase 1)

[android] AndroidKeyStore P-256 key generation (StrongBox, TEE fallback, non-exportable)

Reference — E10-01 acceptance criteria:
- With `failNextGenerate(StrongBoxUnavailable)`, the provider issues exactly one retry with preferStrongBox=false and returns that key.
- If both the StrongBox and the TEE request fail, the provider throws `IdentityKeyError.GenerationFailed` and no key from any other source (software/exportable) is created.
- The StrongBox fallback writes one log line naming the resulting security level and containing no key bytes, alias-independent handle or certificate bytes (UC-02 alternate).
- A second getOrCreateIdentityKey() returns the key with the same alias and public key without calling generate again.
- On the emulator, the real impl generates the key after the StrongBox fallback and `privateKey.encoded` returns null.
- On a StrongBox-capable physical device, KeyInfo reports security level STRONGBOX; on a TEE-only device, isInsideSecureHardware=true (manual gate).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### androidKeyStoreIdentity_teeOnlyDevice_insideSecureHardwareTrue (E10-01, phase 1)

[android] AndroidKeyStore P-256 key generation (StrongBox, TEE fallback, non-exportable)

Reference — E10-01 acceptance criteria:
- With `failNextGenerate(StrongBoxUnavailable)`, the provider issues exactly one retry with preferStrongBox=false and returns that key.
- If both the StrongBox and the TEE request fail, the provider throws `IdentityKeyError.GenerationFailed` and no key from any other source (software/exportable) is created.
- The StrongBox fallback writes one log line naming the resulting security level and containing no key bytes, alias-independent handle or certificate bytes (UC-02 alternate).
- A second getOrCreateIdentityKey() returns the key with the same alias and public key without calling generate again.
- On the emulator, the real impl generates the key after the StrongBox fallback and `privateKey.encoded` returns null.
- On a StrongBox-capable physical device, KeyInfo reports security level STRONGBOX; on a TEE-only device, isInsideSecureHardware=true (manual gate).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### qrScanner_realCameraMacDisplay_decodesWithin3s (E14-10, phase 1)

[android] CameraX QR scanner UI (decoder chosen by E14-23)

Reference — E14-10 acceptance criteria:
- A QR_CODE result with a tandem:// value is accepted and passed to the parser exactly once, even if detected in 10 consecutive frames
- A non-QR format or a non-tandem QR value is ignored with no parser call and no crash
- The fixture bitmap of a tandem:// QR decodes through the chosen decoder to the exact fixture string
- With camera permission denied, the screen shows state CameraPermissionRequired with a grant button and no skip (UC-02 camera exception)
- An accepted scan navigates to the pairing-progress screen
- On a physical device, a QR shown on a Mac display at 30-60 cm decodes within 3 s

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### keystoreClientAuth_strongBoxDevice_readyFiveOfFiveAttempts (E14-18, phase 1)

[android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM)

Reference — E14-18 acceptance criteria:
- Every matrix device reaches Ready (handshake + VersionHello) against the real Mac using its Keystore identity, 5 of 5 attempts
- A StrongBox generation failure falls back to TEE only; no software or exportable key is ever created (unit + emulator)
- One real scan-to-Paired run on the same Wi-Fi completes in < 10 s and is recorded
- Results are committed in docs/testing/device-matrix.md with device, API level, backing (StrongBox/TEE), and outcome

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### keystoreClientAuth_teeOnlyDevice_readyFiveOfFiveAttempts (E14-18, phase 1)

[android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM)

Reference — E14-18 acceptance criteria:
- Every matrix device reaches Ready (handshake + VersionHello) against the real Mac using its Keystore identity, 5 of 5 attempts
- A StrongBox generation failure falls back to TEE only; no software or exportable key is ever created (unit + emulator)
- One real scan-to-Paired run on the same Wi-Fi completes in < 10 s and is recorded
- Results are committed in docs/testing/device-matrix.md with device, API level, backing (StrongBox/TEE), and outcome

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### keystoreClientAuth_api29Device_readyFiveOfFiveAttempts (E14-18, phase 1)

[android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM)

Reference — E14-18 acceptance criteria:
- Every matrix device reaches Ready (handshake + VersionHello) against the real Mac using its Keystore identity, 5 of 5 attempts
- A StrongBox generation failure falls back to TEE only; no software or exportable key is ever created (unit + emulator)
- One real scan-to-Paired run on the same Wi-Fi completes in < 10 s and is recorded
- Results are committed in docs/testing/device-matrix.md with device, API level, backing (StrongBox/TEE), and outcome

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### keystoreClientAuth_samsungDevice_readyFiveOfFiveAttempts (E14-18, phase 1)

[android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM)

Reference — E14-18 acceptance criteria:
- Every matrix device reaches Ready (handshake + VersionHello) against the real Mac using its Keystore identity, 5 of 5 attempts
- A StrongBox generation failure falls back to TEE only; no software or exportable key is ever created (unit + emulator)
- One real scan-to-Paired run on the same Wi-Fi completes in < 10 s and is recorded
- Results are committed in docs/testing/device-matrix.md with device, API level, backing (StrongBox/TEE), and outcome

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### qrPairing_realScanSameWifi_pairedUnder10s (E14-18, phase 1)

[android] Keystore client-auth device matrix test (StrongBox, TEE-only, API 29, OEM)

Reference — E14-18 acceptance criteria:
- Every matrix device reaches Ready (handshake + VersionHello) against the real Mac using its Keystore identity, 5 of 5 attempts
- A StrongBox generation failure falls back to TEE only; no software or exportable key is ever created (unit + emulator)
- One real scan-to-Paired run on the same Wi-Fi completes in < 10 s and is recorded
- Results are committed in docs/testing/device-matrix.md with device, API level, backing (StrongBox/TEE), and outcome

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### oemBatteryKiller_screenOff60minUnrestricted_serviceStillConnected (E20-02, phase 2)

[android] Foreground service (connectedDevice type)

Reference — E20-02 acceptance criteria:
- Merged manifest declares the service with foregroundServiceType="connectedDevice" and the FOREGROUND_SERVICE_CONNECTED_DEVICE and CHANGE_NETWORK_STATE permissions
- With a paired Mac, app launch starts the service in the foreground with its ongoing notification; with no paired Mac the service is not started
- Unpairing the last Mac stops the service and removes its notification
- onStartCommand returns START_STICKY
- After the app process is killed on the emulator (adb shell am kill after moving to background, or kill -9 under adb root), the system restarts the service within 15 s
- Manual gate: on the aggressive-battery OEM device from the device matrix with battery unrestricted, the service is still running and connected after 60 min screen-off

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### oemGuidanceSamsungXiaomi_stepsFollowed_appListedUnrestricted (E20-04, phase 2)

[android] Unrestricted battery onboarding and OEM guidance

Reference — E20-04 acceptance criteria:
- If the app is already ignoring battery optimizations, the battery screen is skipped
- Tapping "Allow" launches ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS; tapping "Skip" advances without launching any intent
- OEM guidance returns a dedicated entry for Samsung, Xiaomi, OnePlus and Huawei and the generic entry for any other manufacturer
- The settings row "Battery optimization" reopens the same screen including the OEM section
- Manual gate: following the Samsung and Xiaomi guidance on the matrix devices results in Tandem listed as Unrestricted in system battery settings

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### phoneReboot_pairedMac_connectedWithin60sOfUnlock (E20-08, phase 2)

[android] Service restart on BOOT_COMPLETED and MY_PACKAGE_REPLACED

Reference — E20-08 acceptance criteria:
- Merged manifest declares RECEIVE_BOOT_COMPLETED and the receiver for android.intent.action.BOOT_COMPLETED
- BOOT_COMPLETED with a paired Mac starts the foreground service; with no paired Mac nothing is started
- Manual gate: after a physical reboot and unlock, the service is running and connected to the Mac within 60 s without opening the app
- The receiver ignores any intent whose action is not BOOT_COMPLETED or MY_PACKAGE_REPLACED: an explicit intent from another app with another action starts nothing (the receiver must be exported, E00-28 allowlist).
- MY_PACKAGE_REPLACED with a paired Mac starts the foreground service; with no paired Mac nothing is started

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### reconnectWifiSwitch_twentyTrials_p95Under5s (E20-12, phase 2)

[tools] Reconnect latency measurement harness and overnight Doze gate

Reference — E20-12 acceptance criteria:
- Harness self-test on fixture logs reports the correct p95 and exits non-zero when p95 > 5 s
- Wi-Fi switch and Mac wake scenarios each report p95 < 5 s over >= 20 trials (PRD Phase 2 exit)
- Over >= 8 h of Doze with the FGS running and battery unrestricted, zero user interaction, every Mac-declared-dead episode is followed by a reconnect within 5 s of the next Doze maintenance window or screen-on; the number of episodes and per-episode latency are recorded
- Quick gate with `adb shell dumpsys deviceidle force-idle` for 10 min, then `unforce` and screen-on, ends Connected within 5 s
- JVM client idle for 120 s against the real Mac server stays connected, with every Mac Heartbeat answered

**Preconditions:** Phone paired with the Mac and Connected; build emits `TandemReconnect` markers (`LogcatReconnectMarkers`); phone attached over adb; two known Wi-Fi networks that both reach the Mac; FGS running, battery unrestricted.
**Steps:** Run `tools/reconnect-harness/scenario-wifi-switch.sh <ssid-a> <pass-a> <ssid-b> <pass-b> 20`. It alternates networks via `adb shell cmd wifi connect-network`, saves the logcat and pipes it through `run.rb --min-trials 20`.
**Pass threshold:** `run.rb` exits 0: at least 20 trials, none unrecovered, p95 < 5 s.
**Evidence required (log excerpt / screen recording / pcap path):** The harness output line (`trials=... p95=...`) plus the saved `wifi-switch.logcat` path.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### reconnectMacWake_twentyTrials_p95Under5s (E20-12, phase 2)

[tools] Reconnect latency measurement harness and overnight Doze gate

Reference — E20-12 acceptance criteria:
- Harness self-test on fixture logs reports the correct p95 and exits non-zero when p95 > 5 s
- Wi-Fi switch and Mac wake scenarios each report p95 < 5 s over >= 20 trials (PRD Phase 2 exit)
- Over >= 8 h of Doze with the FGS running and battery unrestricted, zero user interaction, every Mac-declared-dead episode is followed by a reconnect within 5 s of the next Doze maintenance window or screen-on; the number of episodes and per-episode latency are recorded
- Quick gate with `adb shell dumpsys deviceidle force-idle` for 10 min, then `unforce` and screen-on, ends Connected within 5 s
- JVM client idle for 120 s against the real Mac server stays connected, with every Mac Heartbeat answered

**Preconditions:** Phone paired with the Mac and Connected; build emits `TandemReconnect` markers; phone attached over adb to the Mac running the script; sudo available for `pmset schedule`; Mac on AC power.
**Steps:** Run `tools/reconnect-harness/scenario-mac-wake.sh 20 60`. Each trial schedules a wake with `pmset schedule wake`, runs `pmset sleepnow` and waits; the phone logcat is then piped through `run.rb --min-trials 20`.
**Pass threshold:** `run.rb` exits 0: at least 20 trials, none unrecovered, p95 < 5 s.
**Evidence required (log excerpt / screen recording / pcap path):** The harness output line (`trials=... p95=...`) plus the saved `mac-wake.logcat` path.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### overnightDoze8h_fgsUnrestrictedBattery_reconnectWithin5sOfWake (E20-12, phase 2)

[tools] Reconnect latency measurement harness and overnight Doze gate

Reference — E20-12 acceptance criteria:
- Harness self-test on fixture logs reports the correct p95 and exits non-zero when p95 > 5 s
- Wi-Fi switch and Mac wake scenarios each report p95 < 5 s over >= 20 trials (PRD Phase 2 exit)
- Over >= 8 h of Doze with the FGS running and battery unrestricted, zero user interaction, every Mac-declared-dead episode is followed by a reconnect within 5 s of the next Doze maintenance window or screen-on; the number of episodes and per-episode latency are recorded
- Quick gate with `adb shell dumpsys deviceidle force-idle` for 10 min, then `unforce` and screen-on, ends Connected within 5 s
- JVM client idle for 120 s against the real Mac server stays connected, with every Mac Heartbeat answered

**Preconditions:** Phone paired and Connected, FGS running, battery set to Unrestricted, charger unplugged, screen off, `adb logcat` capturing `TandemReconnect:I` to a file (`adb logcat -v threadtime -s TandemReconnect:I > overnight.logcat`) over Wi-Fi adb or a tethered host; Mac awake.
**Steps:** Leave the phone idle for at least 8 h with zero interaction. In the morning wake the screen, wait 10 s, stop the capture and run `ruby tools/reconnect-harness/run.rb overnight.logcat`.
**Pass threshold:** `run.rb` exits 0: every dead/disconnected episode reached ready (none unrecovered) with p95 < 5 s; episode count and per-episode latency are recorded.
**Evidence required (log excerpt / screen recording / pcap path):** The harness output line, the number of episodes, and `overnight.logcat`.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### adbForceIdle10min_unforceAndScreenOn_connectedWithin5s (E20-12, phase 2)

[tools] Reconnect latency measurement harness and overnight Doze gate

Reference — E20-12 acceptance criteria:
- Harness self-test on fixture logs reports the correct p95 and exits non-zero when p95 > 5 s
- Wi-Fi switch and Mac wake scenarios each report p95 < 5 s over >= 20 trials (PRD Phase 2 exit)
- Over >= 8 h of Doze with the FGS running and battery unrestricted, zero user interaction, every Mac-declared-dead episode is followed by a reconnect within 5 s of the next Doze maintenance window or screen-on; the number of episodes and per-episode latency are recorded
- Quick gate with `adb shell dumpsys deviceidle force-idle` for 10 min, then `unforce` and screen-on, ends Connected within 5 s
- JVM client idle for 120 s against the real Mac server stays connected, with every Mac Heartbeat answered

**Preconditions:** Phone paired and Connected, FGS running, battery Unrestricted, phone attached over adb.
**Steps:** Run `tools/reconnect-harness/scenario-force-idle.sh 10`. It runs `dumpsys deviceidle force-idle` for 10 min, then `unforce`, wakes the screen and pipes the logcat through `run.rb`.
**Pass threshold:** `run.rb` exits 0 (p95 < 5 s, no unrecovered episode); the phone ends Connected within 5 s of screen-on.
**Evidence required (log excerpt / screen recording / pcap path):** The harness output line, the saved `force-idle.logcat` path, and a screenshot of the Connected state.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### forceIdle30min_macHeartbeats_everyHeartbeatAnsweredWithin1s (E20-15, phase 2)

[android] Heartbeat responder, Doze-aware timer, sleep-inclusive dead-peer detection

Reference — E20-15 acceptance criteria:
- Every received Heartbeat is answered with exactly one Heartbeat within 1 s; non-Heartbeat frames get no reply
- While interactive and not idle, a Heartbeat is sent after 15 s without sending; while idle, no Heartbeat, wake lock or alarm is scheduled
- 46 s of elapsedRealtime silence (including device sleep, with wall clock unchanged) emits PeerDead
- A Doze-exit or screen-on event after > 45 s of silence emits PeerDead immediately, before the detector timer fires
- A 1 h forward wall-clock jump with frames still arriving does not emit PeerDead
- The DeviceIdleSource adapter emits the new idle state on ACTION_DEVICE_IDLE_MODE_CHANGED
- Manual gate: under adb force-idle for 30 min, every Mac Heartbeat is answered within 1 s (Mac-side log)

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### cdmPresence_appKilledMacPresent_serviceRestartedWithin60s (E20-16, phase 2)

[android] CompanionDeviceManager association (+ presence restart if E20-03 = go)

Reference — E20-16 acceptance criteria:
- PairingCompleted requests exactly one CDM association for the paired Mac
- Unpairing removes the matching association id
- Creating or removing an association leaves the trust-store record unchanged
- (If E20-03 = go) a presence callback while the service is stopped starts the foreground service; while running it starts nothing
- (If E20-03 = go) Manual gate: after the app is killed, a presence event restarts the service within 60 s on the matrix devices

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### dnsSdBrowse_acrossUtcMidnight_txtIdAndInstanceNameChanged (E21-02, phase 2)

[macos] Advertise _tandem._tcp with rotating TXT id

Reference — E21-02 acceptance criteria:
- The Swift rotating-id implementation matches every E01-20 vector
- TXT contains exactly the keys v (value 1) and the rotating id, nothing else (AC-05)
- Crossing 00:00:00 UTC republishes the new id within 1 s, and no open connection is cancelled by the refresh
- dayIndex is computed in UTC regardless of the Mac's time zone
- The instance name is derived from the rotating id and contains no Mac name, user name or other stable identifier (AC-05)
- Manual gate: dns-sd -B/-L before and after UTC midnight shows a changed TXT id and instance name

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### freshMacUser_firstAdvertise_localNetworkPromptShownOnce (E21-03, phase 2)

[macos] Local Network privacy entries and permission handling

Reference — E21-03 acceptance criteria:
- Info.plist contains NSLocalNetworkUsageDescription and NSBonjourServices containing _tandem._tcp
- A policy-denied advertise error shows the exact explanation text and button
- The button opens the Privacy & Security > Local Network settings URL
- Manual gate: on a fresh macOS user, first advertise shows the Local Network prompt once

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### nsdBrowse_realMacSameWifi_resolvedWithin3s (E21-04, phase 2)

[android] NsdManager browse and resolve

Reference — E21-04 acceptance criteria:
- A found service is resolved to host, port and TXT and emitted as a candidate
- Two transient resolve failures followed by success emit the resolved service after the backoff waits; exhausting retries leaves the browse session active
- A lost service is removed from the candidate set
- Manual gate: a real Mac on the same Wi-Fi is resolved within 3 s of browse start

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### macReboot_launchAtLoginOn_menuBarIconWithin60sOfLogin (E22-03, phase 2)

[macos] Launch at login via SMAppService

Reference — E22-03 acceptance criteria:
- Toggling on calls register once; toggling off calls unregister once
- First successful pairing registers the login item when the user has never set the toggle
- The toggle reflects SMAppService status after it is changed outside the app, on the next Settings appear / app activation (UC-01)
- Status requiresApproval shows the exact approval hint
- Manual gate: with the toggle on, after a full reboot and login the menu bar icon appears within 60 s

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### sandboxedReleaseBuild_pairedPhoneConnects_sessionReadyWithin5s (E22-04, phase 2)

[macos] App Sandbox entitlements for network client/server

Reference — E22-04 acceptance criteria:
- codesign --display --entitlements on the Release build shows exactly app-sandbox, network.server and network.client at this stage
- The sandboxed build launched on the macOS CI runner has its single listening port bound within 10 s (lsof)
- Manual gate: a paired phone reaches session Ready with the sandboxed Release build within 5 s
- `codesign -d --verbose` shows the runtime flag on the Release app and no com.apple.security.cs.* or get-task-allow entitlement.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### ringPhysicalPhone_silentAndDnd_audibleAtMaxVolume (E23-05, phase 2)

[android] Ring handler: max volume overriding DND

Reference — E23-05 acceptance criteria:
- Ring sets STREAM_ALARM to its max and starts looping playback; stop restores the previous alarm volume
- With policy access and filter NONE, the filter becomes ALARMS during the ring and is restored after
- Without policy access, the exact explanation is shown before the policy settings screen is opened
- On the emulator with DND priority mode and policy access, the alarm stream is active at max volume within 1 s of Ring
- Manual gate: a physical phone in silent mode with DND on rings audibly at max volume (UC-06)

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### findPhoneFromMacMenu_silentDndPhone_stopSilencesWithin1s (E23-08, phase 2)

[cross] Status throttle and ring round-trip tests

Reference — E23-08 acceptance criteria:
- A burst of 20 changes in 5 s results in at most 2 DeviceStatus frames received by the Mac within 65 s (leading + one trailing)
- The Ring round trip stops the phone-side alarm within 1 s of the Mac sending RingStop (UC-06)
- A battery or network change outside the throttle window is reflected in the Mac view model within 2 s (UC-05)
- Manual gate: Find Phone from the Mac menu rings a physical phone in silent + DND, and Stop Ringing silences it within 1 s

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### macNotificationBanner_physicalMac_showsTitleAppNameBodyWithin1s (E30-07, phase 3)

[macos] UNUserNotificationCenter presentation via NotificationPresenter seam

Reference — E30-07 acceptance criteria:
- A plain notification produces a request with title = notification title, subtitle = app name, body = text
- A MessagingStyle notification body lists one line per message as "Sender: text"
- The request identifier equals the NotificationPosted key, so an update to the same key replaces rather than stacks the delivered notification
- On a physical Mac with notifications allowed, a posted notification appears as a banner with title, app name, and body within 1 s of receipt
- Every presented string passes the E14-22 sanitizer and the E01-22 caps (title <= 256, body <= 4096 characters, <= 25 senders); on unpair (PeerDataPurgeRegistry, E14-13) all delivered notifications from that phone are removed.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### whatsAppReplyFromMac_physicalPhone_fiveOfFiveDeliveredWithin10s (E30-13, phase 3)

[cross] Phase 3 notification exit test

Reference — E30-13 acceptance criteria:
- 5 of 5 WhatsApp replies sent from the Mac arrive at the WhatsApp contact within 10 s
- 5 of 5 Signal replies sent from the Mac arrive at the Signal contact within 10 s
- 10 of 10 dismissals in each direction remove the peer notification within 1 s
- pcap-audit canary scan of the run finds zero occurrences of the notification canary
- log-audit over both apps' logs for the run finds zero occurrences of the canary or any reply text

**Preconditions:** Paired physical Mac and Android phone on the same Wi-Fi, release builds, session connected; notification access granted on the phone with WhatsApp allowed and content forwarding opted in (F-5.4); Mac notification permission granted; a second device with a WhatsApp contact able to message the phone.
**Steps:**
1. From the contact, send a WhatsApp message to the phone; confirm a banner with the contact name and text appears on the Mac.
2. Use the banner Reply action on the Mac to send a short reply (`R1`); start a stopwatch on send.
3. Confirm the reply is delivered in the WhatsApp contact's chat; note the elapsed time.
4. Repeat steps 1-3 for five replies (`R1`..`R5`).
**Pass threshold:** 5 of 5 replies reach the WhatsApp contact within 10 s of sending from the Mac.
**Evidence required (log excerpt / screen recording / pcap path):** Screen recording of the five replies with timestamps, elapsed times per reply.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### signalReplyFromMac_physicalPhone_fiveOfFiveDeliveredWithin10s (E30-13, phase 3)

[cross] Phase 3 notification exit test

Reference — E30-13 acceptance criteria:
- 5 of 5 WhatsApp replies sent from the Mac arrive at the WhatsApp contact within 10 s
- 5 of 5 Signal replies sent from the Mac arrive at the Signal contact within 10 s
- 10 of 10 dismissals in each direction remove the peer notification within 1 s
- pcap-audit canary scan of the run finds zero occurrences of the notification canary
- log-audit over both apps' logs for the run finds zero occurrences of the canary or any reply text

**Preconditions:** Paired physical Mac and Android phone on the same Wi-Fi, release builds, session connected; notification access granted on the phone with Signal allowed and content forwarding opted in (F-5.4); Mac notification permission granted; a second device with a Signal contact able to message the phone.
**Steps:**
1. From the contact, send a Signal message to the phone; confirm a banner with the contact name and text appears on the Mac.
2. Use the banner Reply action on the Mac to send a short reply (`R1`); start a stopwatch on send.
3. Confirm the reply is delivered in the Signal contact's chat; note the elapsed time.
4. Repeat steps 1-3 for five replies (`R1`..`R5`).
**Pass threshold:** 5 of 5 replies reach the Signal contact within 10 s of sending from the Mac.
**Evidence required (log excerpt / screen recording / pcap path):** Screen recording of the five replies with timestamps, elapsed times per reply.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### dismissSyncBothWays_physicalDevices_tenOfTenUnder1s (E30-13, phase 3)

[cross] Phase 3 notification exit test

Reference — E30-13 acceptance criteria:
- 5 of 5 WhatsApp replies sent from the Mac arrive at the WhatsApp contact within 10 s
- 5 of 5 Signal replies sent from the Mac arrive at the Signal contact within 10 s
- 10 of 10 dismissals in each direction remove the peer notification within 1 s
- pcap-audit canary scan of the run finds zero occurrences of the notification canary
- log-audit over both apps' logs for the run finds zero occurrences of the canary or any reply text

**Preconditions:** Paired physical Mac and Android phone on the same Wi-Fi, release builds, session connected; notification access granted on the phone; Mac notification permission granted; the companion app (E00-22) installed on the phone to post notifications; pcap capture (whole interface) and log capture (`adb logcat`, macOS unified log) running; fresh canary `TANDEM-CANARY-<nonce>` generated by tools/pcap-audit/canary.sh.
**Steps:**
1. Phone-to-Mac: post 10 notifications (`adb shell am broadcast -a dev.tandem.companion.POST --es kind plain --es key k<N>`), dismiss each on the phone, and time until its banner leaves the Mac Notification Center.
2. Mac-to-phone: post 10 more, dismiss each on the Mac, and time until the notification leaves the phone shade.
3. Run the E15-07 notification step of tools/pcap-audit/canary.sh (companion `kind canary` broadcast) inside the capture while both apps run.
4. Run the pcap-audit canary scan on the capture and log-audit (`tools/log-audit/log-audit.sh --canary <canary> --logcat <file> --unified-log <file>`) on both apps' logs, also scanning for every reply text used in the WhatsApp and Signal gates.
**Pass threshold:** 10 of 10 dismissals in each direction remove the peer notification within 1 s; pcap-audit finds zero occurrences of the canary; log-audit finds zero occurrences of the canary or any reply text in either app's logs.
**Evidence required (log excerpt / screen recording / pcap path):** Per-dismissal timings for both directions, pcap path, pcap-audit and log-audit output.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### notificationLatency_twoHundredCompanionPostsSameWifi_p95Under500ms (E30-14, phase 3)

[tools] Notification latency harness: Android to Mac p95 < 500 ms

Reference — E30-14 acceptance criteria:
- Over 200 notifications on the same Wi-Fi, p95 Android-post to Mac-presentation latency is < 500 ms
- Loopback (E15-15) p95 receive-to-presenter latency is < 100 ms over 200 frames
- The clock-offset correction is applied and recorded in the report; a known 250 ms skew is corrected to within 5 ms
- p95 uses the nearest-rank method over all samples
- The harness logs only sequence numbers and timings, never notification content (invariant 7)

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### lockScreenHiding_physicalLockedMac_lockScreenShowsAppNameOnly (E30-15, phase 3)

[macos] Hide notification content while the Mac is locked

Reference — E30-15 acceptance criteria:
- With the option on and the screen locked, the presented request has title = app name, subtitle = "", body = ""
- With the option on and the screen unlocked, or the option off, full title and body are presented
- Unlocking does not re-post notifications presented while locked
- Toggling the option applies to the next notification without reconnecting (UC-11)
- The production ScreenLockState reports locked after a `com.apple.screenIsLocked` notification and unlocked after `com.apple.screenIsUnlocked`
- On a physical Mac with the option on, a notification arriving while locked shows only the app name on the lock screen

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### macNotificationReply_physicalMac_replyActionShowsTextField (E30-17, phase 3)

[macos] Notification categories: phone actions, text-input reply, custom dismiss

Reference — E30-17 acceptance criteria:
- A post with 2 actions is assigned a category whose actions match the titles in order
- A RemoteInput-capable action registers a UNTextInputNotificationAction
- A post without actions is assigned the dismiss-only category
- Every registered category includes the customDismissAction option
- Two posts with identical action sets share one category identifier
- On a physical Mac, the reply action on a companion `actions` notification shows a text field

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### sensitiveClip_android13Device_noPreviewOverlayThreeOfThree (E31-05, phase 3)

[android] Receive and write clipboard with sensitive flag

Reference — E31-05 acceptance criteria:
- A received ClipboardText becomes the primary clip with identical text
- On API 33+, a sensitive ClipboardText's ClipDescription extras contain EXTRA_IS_SENSITIVE = true
- On API 33+, a non-sensitive ClipboardText has no EXTRA_IS_SENSITIVE extra
- On API 29, a sensitive ClipboardText is written without the extra and without error
- On a physical Android 13+ device, a sensitive clip shows no clipboard preview overlay

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### clipboardRoundTripCanary_physicalDevices_oneFramePerDirectionIn30s (E31-10, phase 3)

[cross] Clipboard exit test: no echo loop, concealed never leaves Mac

Reference — E31-10 acceptance criteria:
- On physical devices, the round-trip canary produces exactly one CLIPBOARD frame per direction within 30 s and no further frames
- Loopback: after a ConcealedType item is placed, the peer receives 0 CLIPBOARD frames within 5 s of virtual time
- During the physical concealed-item test the phone clipboard never contains the concealed canary and the phone's CLIPBOARD receive counter does not change
- pcap-audit canary scan (E15-06) of the E15-07 clipboard step finds zero occurrences
- log-audit (E15-17) over both apps' logs for the session finds zero occurrences of either canary

**Preconditions:** Paired physical Mac and Android phone on the same Wi-Fi, release builds, clipboard sync enabled on both, session connected; pcap capture and log capture running (tools/pcap-audit, tools/log-audit); fresh canary string `CANARY-CLIP-<random>` generated by tools/pcap-audit/canary.sh.
**Steps:**
1. On the Mac, copy the canary text. Wait up to 30 s; confirm the phone clipboard now holds it (paste into any field).
2. Do not touch either clipboard for 30 s more; note both apps' CLIPBOARD frame counters (Mac: Diagnostics; phone: debug counter).
3. On the phone, copy a second canary `CANARY-CLIP2-<random>`. Wait up to 30 s; confirm the Mac pasteboard holds it.
4. Wait 60 s idle; re-read both counters.
5. Run pcap-audit canary scan on the capture and log-audit on both apps' logs for both canaries.
**Pass threshold:** Exactly one CLIPBOARD frame per direction within 30 s of each copy and zero further frames in the idle windows (no echo loop); pcap-audit and log-audit find zero occurrences of either canary.
**Evidence required (log excerpt / screen recording / pcap path):** Counter readings before/after each step, pcap path, pcap-audit and log-audit output.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### concealedCanaryOnMac_physicalPhone_receiveCounterUnchanged (E31-10, phase 3)

[cross] Clipboard exit test: no echo loop, concealed never leaves Mac

Reference — E31-10 acceptance criteria:
- On physical devices, the round-trip canary produces exactly one CLIPBOARD frame per direction within 30 s and no further frames
- Loopback: after a ConcealedType item is placed, the peer receives 0 CLIPBOARD frames within 5 s of virtual time
- During the physical concealed-item test the phone clipboard never contains the concealed canary and the phone's CLIPBOARD receive counter does not change
- pcap-audit canary scan (E15-06) of the E15-07 clipboard step finds zero occurrences
- log-audit (E15-17) over both apps' logs for the session finds zero occurrences of either canary

**Preconditions:** Same setup as the round-trip canary gate; a password manager (or `pbcopy`-style helper that sets `org.nspasteboard.ConcealedType`) available on the Mac; canary `CANARY-CONCEALED-<random>`; pcap and log capture running.
**Steps:**
1. Note the phone's CLIPBOARD receive counter and current phone clipboard content.
2. On the Mac, place the canary on the pasteboard flagged `org.nspasteboard.ConcealedType` (e.g. copy a password from the password manager, or write the item with that type).
3. Wait 30 s. Paste into a phone text field and re-read the phone's CLIPBOARD receive counter.
4. Run pcap-audit canary scan and log-audit on both apps' logs for the canary.
**Pass threshold:** Phone clipboard never contains the canary, the phone's CLIPBOARD receive counter is unchanged, and log-audit finds zero occurrences of the canary in either app's logs.
**Evidence required (log excerpt / screen recording / pcap path):** Counter readings before/after, screen recording of the phone paste attempt, log-audit output.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### fourGbTransfer_phoneToMacWifiDropAtHalf_resumesShaMatchesMemoryUnder64MiB (E40-14, phase 4)

[tools] 4 GB transfer with forced disconnect

Reference — E40-14 acceptance criteria:
- Integration, both directions, 256 MiB, abrupt close at 50 %; the resume request's fromOffset is > 0, re-sent bytes are ≤ 4 MiB, and the received SHA-256 equals the source
- Manual, phone → Mac and Mac → phone, 4 GB; the transfer resumes without user action within 60 s of Wi-Fi returning, from an offset ≥ the bytes acknowledged before the disconnect minus 4 MiB, and `shasum -a 256` on both ends matches
- Manual; peak memory during the transfer stays ≤ 64 MiB above the pre-transfer idle value (Android `dumpsys meminfo` total PSS; Mac `footprint` of the agent)
- Manual; no `.part` file remains in either staging directory after completion

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### fourGbTransfer_macToPhoneWifiDropAtHalf_resumesShaMatchesMemoryUnder64MiB (E40-14, phase 4)

[tools] 4 GB transfer with forced disconnect

Reference — E40-14 acceptance criteria:
- Integration, both directions, 256 MiB, abrupt close at 50 %; the resume request's fromOffset is > 0, re-sent bytes are ≤ 4 MiB, and the received SHA-256 equals the source
- Manual, phone → Mac and Mac → phone, 4 GB; the transfer resumes without user action within 60 s of Wi-Fi returning, from an offset ≥ the bytes acknowledged before the disconnect minus 4 MiB, and `shasum -a 256` on both ends matches
- Manual; peak memory during the transfer stays ≤ 64 MiB above the pre-transfer idle value (Android `dumpsys meminfo` total PSS; Mac `footprint` of the agent)
- Manual; no `.part` file remains in either staging directory after completion

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### noStarvation_realWifiFourGbTransfer_notifyP95Under500ms (E40-15, phase 4)

[tools] Flow-control no-starvation test

Reference — E40-15 acceptance criteria:
- Integration; NOTIFY p95 < 100 ms and max < 500 ms over ≥ 200 frames while the FILES transfer is in progress
- Integration; FILES throughput is > 0 in every 1 s window during NOTIFY bursts
- Manual, E30-14 harness on the same Wi-Fi: NOTIFY p95 < 500 ms during a saturating 4 GB transfer (UC-16).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### finderServices_sendToPhoneChosen_offerStartsWithinFiveSeconds (E40-21, phase 4)

[macos] Finder Services "Send to phone" entry point

Reference — E40-21 acceptance criteria:
- The app Info.plist declares the "Send to phone" service with send type `public.item`
- A pasteboard holding two file URLs starts two FileOffers
- A pasteboard with no file URL starts no FileOffer and returns an error string
- In Finder, right-click → Services lists "Send to phone" and choosing it starts an offer within 5 s (manual)

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### shareExtension_previewShareMenu_offerStartsWithinFiveSeconds (E40-22, phase 4)

[macos] Share extension target "Send to phone"

Reference — E40-22 acceptance criteria:
- The extension Info.plist activation rule accepts 1..20 files
- The extension binary links neither Network.framework nor the transport package
- Two files enqueued by the extension are dequeued by the agent in order, starting two FileOffers, and their App Group copies are deleted after completion or cancel
- From Preview's Share menu, "Send to phone" starts an offer within 5 s (manual)
- The extension entitlements are exactly app-sandbox and application-groups.
- The agent rejects a queue entry that is a symlink, resolves outside the queue directory, is not a regular file, or exceeds 20 files per request; the wake notification carries no payload.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### partialAccess_selectTwoMoreOnPhone_macListsExactlyFiveItems (E41-08, phase 4)

[android] Partial-access and paging correctness test

Reference — E41-08 acceptance criteria:
- Emulator with only READ_MEDIA_VISUAL_USER_SELECTED granted; PhotoPageResult.access is PARTIAL and a thumb request for a seeded, unselected id returns ACCESS_DENIED
- Emulator with full access; paging the 500 seeded images at limit 100 yields exactly 500 unique ids in 5 pages
- Manual, Android 14+ device, partial access with 3 photos selected; the Mac's "Select more on phone" posts the notification, selecting 2 more makes exactly 5 items listed on the Mac's next refresh

**Preconditions:** Android 14+ phone paired with the Mac and Connected; Tandem granted only "Select photos and videos" with exactly 3 photos selected; photo browser open on the Mac.
**Steps:** On the Mac tap "Select more on phone" and confirm the phone posts the select-more notification. Tap it, choose 2 more photos in the system picker, return to Tandem. Refresh the Mac photo browser.
**Pass threshold:** The notification appears on the phone and, after the refresh, the Mac lists exactly 5 items (the 3 original plus the 2 new).
**Evidence required (log excerpt / screen recording / pcap path):** Screen recording of the phone notification and picker plus a Mac screenshot of the 5-item grid.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### smsSender_realCarrierTwoPartSend_deliveredWithin30s (E50-04, phase 5)

[android] SmsManager multipart send with delivery status

Reference — E50-04 acceptance criteria:
- A 200-character GSM-7 body divides into 2 parts; a 100-character UCS-2 body divides into 2 parts (67 characters per part).
- All parts RESULT_OK yields exactly one SendSmsStatus{SENT}; any failed part yields exactly one SendSmsStatus{FAILED} with that part's errorCode.
- Each of the five SmsManager result codes above maps to a distinct errorCode; RESULT_ERROR_NO_SERVICE maps to NO_SERVICE.
- Delivery reports for all parts yield SendSmsStatus{DELIVERED}.
- SEND_SMS not granted yields FAILED/PERMISSION_DENIED without calling SmsSender.
- The SENT status carries the providerMessageId of the system-written row, or 0 when none is found within 5 s.
- Log lines emitted on failure contain the result code and clientMessageId only.
- Physical phone with SIM: a 2-part message to a second phone reaches DELIVERED within 30 s, and the provider gains exactly one type SENT row written by the system.
- A body over 1600 characters yields FAILED/TOO_LONG, and an 11th send within 60 s yields FAILED/RATE_LIMITED, both without calling SmsSender.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### smsSender_nonDefaultAppSend_systemWritesOneSentProviderRow (E50-04, phase 5)

[android] SmsManager multipart send with delivery status

Reference — E50-04 acceptance criteria:
- A 200-character GSM-7 body divides into 2 parts; a 100-character UCS-2 body divides into 2 parts (67 characters per part).
- All parts RESULT_OK yields exactly one SendSmsStatus{SENT}; any failed part yields exactly one SendSmsStatus{FAILED} with that part's errorCode.
- Each of the five SmsManager result codes above maps to a distinct errorCode; RESULT_ERROR_NO_SERVICE maps to NO_SERVICE.
- Delivery reports for all parts yield SendSmsStatus{DELIVERED}.
- SEND_SMS not granted yields FAILED/PERMISSION_DENIED without calling SmsSender.
- The SENT status carries the providerMessageId of the system-written row, or 0 when none is found within 5 s.
- Log lines emitted on failure contain the result code and clientMessageId only.
- Physical phone with SIM: a 2-part message to a second phone reaches DELIVERED within 30 s, and the provider gains exactly one type SENT row written by the system.
- A body over 1600 characters yields FAILED/TOO_LONG, and an 11th send within 60 s yields FAILED/RATE_LIMITED, both without calling SmsSender.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### smsSend_dualSimSecondSimSelected_recipientSeesSecondSimNumber (E50-05, phase 5)

[android] Multi-SIM subscription chooser for send + SimList

Reference — E50-05 acceptance criteria:
- With two fake subscriptions, subscriptionId=2 sends through the subscription-2 sender.
- With one active SIM and no subscriptionId, the default sender is used.
- With two SIMs, no subscriptionId and no valid default SMS subscription, the status is FAILED/SUBSCRIPTION_REQUIRED and nothing is sent.
- An unknown subscriptionId yields FAILED/INVALID_SUBSCRIPTION.
- A subscription change publishes an updated SimList with the new entries.
- Physical dual-SIM phone: a send with SIM 2 selected is received by the recipient from SIM 2's number.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### e2eSms_realInboundSms_visibleInMacThreadListUnder2s (E50-10, phase 5)

[cross] End-to-end SMS sync + send integration test

Reference — E50-10 acceptance criteria:
- After initial sync of the 5k fixture the Mac store holds exactly 5000 unique messages.
- A connection drop after page 10 followed by reconnect ends with exactly 5000 messages in the Mac store.
- A row inserted into the fake source is in the Mac store within 2 s (UC-18).
- A Mac SendSmsRequest reaches RecordingSmsSender with the composed body and address; fake sent+delivery results leave the Mac message in state DELIVERED within 2 s.
- Physical phone: an SMS from a second phone appears in the Mac thread list < 2 s in 10 of 10 trials (UC-18).
- Physical phone: a Mac-composed SMS reaches the recipient and the Mac shows DELIVERED.
- Physical phone in airplane mode with Wi-Fi re-enabled: a Mac send shows FAILED on the Mac within 10 s (UC-19).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### e2eSms_macComposeToRealRecipient_deliveredShownOnMac (E50-10, phase 5)

[cross] End-to-end SMS sync + send integration test

Reference — E50-10 acceptance criteria:
- After initial sync of the 5k fixture the Mac store holds exactly 5000 unique messages.
- A connection drop after page 10 followed by reconnect ends with exactly 5000 messages in the Mac store.
- A row inserted into the fake source is in the Mac store within 2 s (UC-18).
- A Mac SendSmsRequest reaches RecordingSmsSender with the composed body and address; fake sent+delivery results leave the Mac message in state DELIVERED within 2 s.
- Physical phone: an SMS from a second phone appears in the Mac thread list < 2 s in 10 of 10 trials (UC-18).
- Physical phone: a Mac-composed SMS reaches the recipient and the Mac shows DELIVERED.
- Physical phone in airplane mode with Wi-Fi re-enabled: a Mac send shows FAILED on the Mac within 10 s (UC-19).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### e2eSms_airplaneModeWithWifiSend_failedShownOnMacWithin10s (E50-10, phase 5)

[cross] End-to-end SMS sync + send integration test

Reference — E50-10 acceptance criteria:
- After initial sync of the 5k fixture the Mac store holds exactly 5000 unique messages.
- A connection drop after page 10 followed by reconnect ends with exactly 5000 messages in the Mac store.
- A row inserted into the fake source is in the Mac store within 2 s (UC-18).
- A Mac SendSmsRequest reaches RecordingSmsSender with the composed body and address; fake sent+delivery results leave the Mac message in state DELIVERED within 2 s.
- Physical phone: an SMS from a second phone appears in the Mac thread list < 2 s in 10 of 10 trials (UC-18).
- Physical phone: a Mac-composed SMS reaches the recipient and the Mac shows DELIVERED.
- Physical phone in airplane mode with Wi-Fi re-enabled: a Mac send shows FAILED on the Mac within 10 s (UC-19).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### e2eContacts_realPhoneContactEdit_newNameOnMacWithin10s (E51-07, phase 5)

[cross] End-to-end contacts sync integration test

Reference — E51-07 acceptance criteria:
- After initial sync the Mac cache holds 500 contacts with field values equal to the fixture.
- Editing one fixture contact then deleting another results in the Mac cache reflecting both within 2 s, with one updated record and one tombstone sent (no full resync).
- Physical phone: a contact edited on the phone shows its new name in the Mac thread list within 10 s.

**Preconditions:** Physical phone paired with the Mac, session Ready; READ_CONTACTS granted; initial contacts sync complete; Messages thread list open on the Mac showing a thread with a known contact.
**Steps:** 1. On the phone, rename that contact in the Contacts app. 2. Start a stopwatch on save. 3. Watch the Mac thread list until the thread shows the new name; stop the stopwatch. 4. Repeat 3 times.
**Pass threshold:** New name appears on the Mac within 10 s in all 3 runs, with no manual refresh and no full resync.
**Evidence required (log excerpt / screen recording / pcap path):** Screen recording of phone and Mac with a visible clock; redacted log excerpt showing one incremental ContactsSyncResponse (no names).

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### incomingCall_physicalPhoneWithSim_macAlertWithin1sP95 (E52-08, phase 5)

[cross] Device-level test: call control latency and correctness

Reference — E52-08 acceptance criteria:
- Over 20 incoming calls the Mac alert appears within 1 s of the phone starting to ring at p95.
- Answer from the Mac connects the call within 2 s with audio on the phone.
- Decline from the Mac stops ringing on the phone within 2 s.
- Hang Up from the Mac ends an active call within 2 s.
- Place call from the Mac with the phone locked and app backgrounded starts dialing within 3 s, or the Mac shows the needs-phone-tap state within 3 s (UC-21).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### incomingCall_answerFromMac_callConnectsWithin2s (E52-08, phase 5)

[cross] Device-level test: call control latency and correctness

Reference — E52-08 acceptance criteria:
- Over 20 incoming calls the Mac alert appears within 1 s of the phone starting to ring at p95.
- Answer from the Mac connects the call within 2 s with audio on the phone.
- Decline from the Mac stops ringing on the phone within 2 s.
- Hang Up from the Mac ends an active call within 2 s.
- Place call from the Mac with the phone locked and app backgrounded starts dialing within 3 s, or the Mac shows the needs-phone-tap state within 3 s (UC-21).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### incomingCall_declineFromMac_ringingStopsWithin2s (E52-08, phase 5)

[cross] Device-level test: call control latency and correctness

Reference — E52-08 acceptance criteria:
- Over 20 incoming calls the Mac alert appears within 1 s of the phone starting to ring at p95.
- Answer from the Mac connects the call within 2 s with audio on the phone.
- Decline from the Mac stops ringing on the phone within 2 s.
- Hang Up from the Mac ends an active call within 2 s.
- Place call from the Mac with the phone locked and app backgrounded starts dialing within 3 s, or the Mac shows the needs-phone-tap state within 3 s (UC-21).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### activeCall_hangUpFromMac_callEndsWithin2s (E52-08, phase 5)

[cross] Device-level test: call control latency and correctness

Reference — E52-08 acceptance criteria:
- Over 20 incoming calls the Mac alert appears within 1 s of the phone starting to ring at p95.
- Answer from the Mac connects the call within 2 s with audio on the phone.
- Decline from the Mac stops ringing on the phone within 2 s.
- Hang Up from the Mac ends an active call within 2 s.
- Place call from the Mac with the phone locked and app backgrounded starts dialing within 3 s, or the Mac shows the needs-phone-tap state within 3 s (UC-21).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### placeCall_fromMacPhoneLocked_dialsOrNeedsTapWithin3s (E52-08, phase 5)

[cross] Device-level test: call control latency and correctness

Reference — E52-08 acceptance criteria:
- Over 20 incoming calls the Mac alert appears within 1 s of the phone starting to ring at p95.
- Answer from the Mac connects the call within 2 s with audio on the phone.
- Decline from the Mac stops ringing on the phone within 2 s.
- Hang Up from the Mac ends an active call within 2 s.
- Place call from the Mac with the phone locked and app backgrounded starts dialing within 3 s, or the Mac shows the needs-phone-tap state within 3 s (UC-21).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### mediaIsolation_mirrorDuring1GbTransferOn5GhzWifi_p95LatencyUnder120ms (E60-07, phase 6)

[cross] Media connection isolation from control-channel congestion

Reference — E60-07 acceptance criteria:
- On the E15-15 harness, p95 synthetic MediaFrame delivery delay with the control connection saturated is within 10 ms of the unsaturated baseline and under 120 ms.
- On physical devices over 5 GHz Wi-Fi, mirroring during a 1 GB file transfer keeps p95 end-to-end latency under 120 ms (E61-08 method).

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### mirroring1080pOn5GhzWifi_sixtySecondRun_atLeast30FpsAndP95Under120ms (E61-08, phase 6)

[cross] Mirroring performance harness: fps + end-to-end latency

Reference — E61-08 acceptance criteria:
- The Mac overlay decoder recovers frame index and clock value from the checked-in fixture frame produced by the Android overlay encoder, exactly.
- The clock-offset estimator on fixture round trips returns an offset within half the minimum RTT of the true offset.
- The report computes sustained fps and p95 latency from a sample set; fixture values match expected numbers exactly.
- A 60 s harness run at 1080p over 5 GHz Wi-Fi on the device matrix (E00-23) reports sustained ≥30 fps and p95 end-to-end latency under 120 ms (manual device gate).

**Preconditions:** Physical phone and Mac from the device matrix (E00-23), paired, on the same 5 GHz Wi-Fi network with no other heavy traffic. Debug builds of both apps with the timestamp overlay enabled on the phone encoder (`TimestampOverlayEncoder`, 8x8 px cells at the top-left of each frame). Phone display set to 1080p encoder output (long edge 1920).
**Steps:**
1. Start a mirror session from the Mac (Mirror quick action) and accept the phone prompt.
2. Run the clock-sync probe (`ClockRoundTrip` samples); the Mac derives the phone-minus-Mac offset with `ClockOffsetEstimator` (minimum-RTT sample).
3. Let the session run for 60 s. The Mac decodes every received frame with `TimestampOverlayDecoder` and records `FrameSample(phoneClockMs, receivedMs)`.
4. Build the `LatencyReport` from the samples and the offset; record sustained fps and p95 latency.
**Pass threshold:** Sustained fps >= 30 and p95 end-to-end latency < 120 ms over the 60 s run.
**Evidence required (log excerpt / screen recording / pcap path):** Report values (fps, p95, offset, minimum RTT, sample count) and the device and network used.

| | | | |


### remoteTap_twentyGridTargets_allHitWithin10px (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### remoteSwipe_tenSwipesOnList_allScrollInDragDirection (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### remoteTextEntry_fiftyCharString_fieldContainsExactText (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### remoteGlobalActions_backHomeRecents_eachEffectiveWithin1s (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### remoteInputIndicator_wholeSession_visibleUntilStop (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### remoteInputNegativeControl_afterSessionStop_zeroInjectionsTenDropLogs (E62-09, phase 6)

[cross] End-to-end remote input device test

Reference — E62-09 acceptance criteria:
- 20 of 20 taps on the grid targets register on the intended target, each within 10 px of the target center, portrait and landscape.
- 10 of 10 swipes scroll the list in the dragged direction.
- Entering a 50-character string leaves the EditText containing exactly that string.
- BACK, HOME and RECENTS each take effect within 1 s of the Mac action (5 of 5 each).
- The on-phone indicator is visible for the entire session and gone within 1 s of stop.
- Negative control: after stopping the mirror session, 10 sent InputEvents produce zero injections and 10 drop log entries.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### scrcpyInputPath_e62DeviceSequence_meetsSameThresholds (E62-10, phase 6)

[android] Alternative input path via scrcpy (P2, gated on ADR-006)

Reference — E62-10 acceptance criteria:
- Not started unless ADR-006 explicitly authorizes it.
- If implemented: the scrcpy path refuses injection with no active user-started mirror session or with the on-phone indicator hidden, passes an equivalent of E62-08's mitm-lab scenarios, and reaches parity with E62-09's manual thresholds.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### androidEgressAudit_physicalPhone24hCapture_onlyMacTandemPortFlows (E71-14, phase 7)

[tools] Release audit: network egress audit (the apps talk only to each other)

Reference — E71-14 acceptance criteria:
- The Mac capture of the Tandem processes contains only flows to the phone address on the Tandem port.
- On the emulator, every socket owned by the app UID during the session has the Mac address and Tandem port as remote endpoint.
- Manual gate: a 24 h per-app capture on a physical phone shows only flows to the paired Mac on the Tandem port.
- The parser exits non-zero on a fixture capture containing a flow to a third-party host.

**Preconditions:** Release-build phone paired with the Mac; PCAPdroid installed; the Mac's LAN address and Tandem port known; phone in normal daily use for the 24 h window.
**Steps:**
1. In PCAPdroid select only the Tandem app and start a PCAP capture (not "dump to remote").
2. Use the phone normally for 24 h with the Tandem app running and the Mac reachable at times.
3. Stop the capture and export the pcap.
4. Convert and audit: `tshark -r <capture.pcap> -T fields -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst -e tcp.srcport -e tcp.dstport -e udp.srcport -e udp.dstport -Y "tcp or udp" > flows.tsv && ruby tools/release-audit/egress-audit.rb flows --side phone --peer <mac-address> --port <tandem-port> flows.tsv`
**Pass threshold:** `egress-audit.rb` exits 0: every flow is TCP between the phone and the paired Mac's Tandem port; no other host, port, or UDP.
**Evidence required (log excerpt / screen recording / pcap path):** pcap path and the `egress-audit.rb` output.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### mediaControl_realPlaybackPauseFromMac_takesEffectWithin1s (E72-02, phase 7)

[android] Media control: MediaSession bridge + media-control proto (F-10.1, P2)

Reference — E72-02 acceptance criteria:
- Media-control vectors round-trip on both codecs.
- A received PlayPause command calls pause() on the active session's transport controls when playing and play() when paused.
- An active-session metadata change sends one NowPlaying message with title, artist and playback state.
- Without notification-listener access no NowPlaying message is sent and the Mac is told the capability is unavailable.
- On a physical phone, pausing real media playback from the Mac takes effect within 1 s.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### usbTransport_realCableAttach_helloWithin5s (E72-06, phase 7)

[android] USB transport (F-10.3, P2)

Reference — E72-06 acceptance criteria:
- The E12-13 handshake + Hello + frame round-trip scenario passes over the USB ByteStream with real TLS.
- A peer whose SPKI is not pinned fails the handshake and no application frame is sent.
- The USB transport opens no listening socket (E00-14 rule stays green).
- On a physical phone and Mac over a cable, a control session reaches Hello within 5 s of attach.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


### focusSync_realMacFocusToggle_phoneDndWithin2s (E72-09, phase 7)

[macos] Focus/DND sync: Focus-state sender (F-10.2, P2)

Reference — E72-09 acceptance criteria:
- A Focus change sends exactly one FocusState message with the new state.
- An unchanged Focus state sends nothing.
- On a physical Mac and phone, toggling Focus updates the phone's DND within 2 s.

**Preconditions:** _TBD_
**Steps:** _TBD_
**Pass threshold:** _TBD_
**Evidence required (log excerpt / screen recording / pcap path):** _TBD_

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


## Contacts PII log audit (E51-08)

Not a `manual:` entry, so not managed by `tools/planning/manual_gates.rb`. Physical-phone session for
`logAudit_physicalPhoneContactsCanarySession_zeroMatchesInLogcatAndMacLog`.

**Preconditions:** Paired physical Mac and Android phone, release builds, contacts sync enabled, nonce `TANDEM-CANARY-<random>` generated by tools/pcap-audit/canary.sh; logcat and Mac unified log capture running.
**Steps:**
1. On the phone, add a contact with the canary in its name (`TANDEM-CANARY-<n> Alice`) and email (`TANDEM-CANARY-<n>@example.com`) and a number ending in the nonce digits.
2. Wait for the contact to appear on the Mac; edit its name once, then delete it.
3. Stop captures; run `tools/log-audit/log-audit.sh --canary <canary> --logcat <logcat.txt> --unified-log <mac-unified.log>`.
**Pass threshold:** log-audit exits 0 with zero matches in logcat and the Mac unified log.
**Evidence required:** log-audit output, capture file paths.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |


## SMS PII log audit (E50-11)

Not a `manual:` entry, so not managed by `tools/planning/manual_gates.rb`. Physical-phone session for
`logAudit_physicalPhoneSmsCanarySession_zeroMatchesInLogcatAndMacLog`.

**Preconditions:** Paired physical Mac and Android phone, release builds, SMS sync enabled, nonce `TANDEM-CANARY-<random>` generated by tools/pcap-audit/canary.sh; logcat and Mac unified log capture running; second phone available.
**Steps:**
1. From the second phone, send an SMS with body `TANDEM-CANARY-<n>` to the paired phone; wait for it on the Mac.
2. From the Mac, send an SMS with body `TANDEM-CANARY-<n>` to the second phone's number (use a number ending in the nonce digits as the canary number where possible).
3. Stop captures; run `tools/log-audit/log-audit.sh --canary <canary> --logcat <logcat.txt> --unified-log <mac-unified.log>`.
**Pass threshold:** log-audit exits 0 with zero body or number matches in logcat and the Mac unified log.
**Evidence required:** log-audit output, capture file paths.

| Date | Build SHA | Device | Result |
|---|---|---|---|
| | | | |
