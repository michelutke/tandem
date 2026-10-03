package dev.tandem.core.discovery

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager

// E21-06 fixture (permanent): proves DiscoveryTrustBoundary fires when the discovery module
// constructs or touches the pin verifier itself.
internal fun discoveryOwnedVerifier(pinSource: PinSource): PinningTrustManager = PinningTrustManager(pinSource)
