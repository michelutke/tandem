package dev.tandem.app.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.shell.PairingFlow
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.AndroidKeyStoreIdentityKeyStore
import dev.tandem.core.crypto.IdentityKeyProvider
import dev.tandem.core.pairing.PairingState
import dev.tandem.core.pairing.rotation.RotationKeys
import kotlinx.coroutines.sync.Mutex
import javax.inject.Singleton

/** The one rotation [Mutex] and [RotationComposition] per identity (E70-15). */
@Module
@InstallIn(SingletonComponent::class)
object RotationModule {
    @Provides
    @Singleton
    fun rotationLock(): Mutex = Mutex()

    @Provides
    @Singleton
    fun rotationComposition(
        activeIdentityAlias: ActiveIdentityAlias,
        rotationLock: Mutex,
        pairingFlow: PairingFlow,
    ): RotationComposition {
        val keyStore = AndroidKeyStoreIdentityKeyStore(AppClock.system)
        return RotationComposition(
            keys = RotationKeys(keyStore, IdentityKeyProvider(keyStore), activeIdentityAlias),
            rotationLock = rotationLock,
            pairingInProgress = { pairingFlow.state.value != PairingState.Idle },
        )
    }
}
