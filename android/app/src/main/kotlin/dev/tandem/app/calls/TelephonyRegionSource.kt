package dev.tandem.app.calls

import android.telephony.TelephonyManager
import dev.tandem.feature.contacts.RegionSource
import java.util.Locale

/** Default region for national-format numbers: SIM country, then network country, then the locale's. */
class TelephonyRegionSource(
    private val telephonyManager: TelephonyManager,
) : RegionSource {
    override fun defaultRegion(): String =
        listOf(telephonyManager.simCountryIso, telephonyManager.networkCountryIso)
            .firstOrNull { it.isNotBlank() }
            ?.uppercase(Locale.ROOT)
            ?: Locale.getDefault().country.ifBlank { Locale.US.country }
}
