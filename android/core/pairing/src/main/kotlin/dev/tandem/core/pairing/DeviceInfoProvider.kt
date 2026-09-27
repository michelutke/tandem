package dev.tandem.core.pairing

import android.os.Build

/**
 * This phone's `PairRequest.deviceInfo.displayName`/`.model` (E14-06; SPEC.md §2 "Frame order on a
 * pairing-candidate connection", step 3). MUST NOT report a hardware identifier — no ANDROID_ID,
 * serial, IMEI, MAC address or account (`docs/planning/backlog/phase-1.yaml` E14-06's
 * `pairRequest_deviceInfo_containsNoHardwareIdentifiers`). Inject it; tests use a fake with fixed
 * strings.
 */
interface DeviceInfoProvider {
    fun displayName(): String

    fun model(): String
}

/** Production implementation backed by [Build.MANUFACTURER]/[Build.MODEL] only. */
object SystemDeviceInfoProvider : DeviceInfoProvider {
    override fun displayName(): String = "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun model(): String = Build.MODEL
}
