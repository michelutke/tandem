package dev.tandem.feature.notifications

import java.security.KeyStore

// E10-14 fixture (permanent, no add-and-revert): proves KeyMaterialOnlyInCrypto fires when a
// feature module reaches for AndroidKeyStore directly instead of going through core/crypto.
internal fun androidKeyStoreFixture(): KeyStore =
    KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
