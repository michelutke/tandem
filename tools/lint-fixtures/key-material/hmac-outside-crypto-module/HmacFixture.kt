package dev.tandem.feature.notifications

import javax.crypto.Mac

// E10-14 fixture (permanent, no add-and-revert): proves KeyMaterialOnlyInCrypto fires when a
// feature module computes HMAC-SHA256 directly instead of going through core/crypto.
internal fun hmacFixture(): Mac = Mac.getInstance("HmacSHA256")
