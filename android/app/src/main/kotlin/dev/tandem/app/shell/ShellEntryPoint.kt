package dev.tandem.app.shell

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.connection.ConnectionStatusViewModel
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.pairing.UnpairAction
import dev.tandem.core.storage.trust.TrustStore

/** Hilt graph nodes [dev.tandem.app.MainActivity] builds its [AppShellDependencies] from. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface ShellEntryPoint {
    fun trustStore(): TrustStore

    fun connectionStatusViewModel(): ConnectionStatusViewModel

    fun pairingAddressStore(): PairingAddressStore

    fun unpairAction(): UnpairAction

    fun sessionRegistry(): SessionRegistry
}
