package dev.tandem.feature.contacts

/**
 * E51-03 seam for the default region used to parse national-format numbers. The production
 * implementation resolves SIM country, then network country, then Locale; tests inject a fixed
 * region.
 */
fun interface RegionSource {
    /** Upper-case ISO 3166-1 alpha-2 region code, e.g. "CH". */
    fun defaultRegion(): String
}
