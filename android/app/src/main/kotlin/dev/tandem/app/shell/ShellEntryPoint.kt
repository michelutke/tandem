package dev.tandem.app.shell

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.connection.ConnectionOrchestrator
import dev.tandem.app.connection.ConnectionStatusViewModel
import dev.tandem.app.connection.RePairNoticeStore
import dev.tandem.app.connection.RevokedNoticeStore
import dev.tandem.app.di.RotationComposition
import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.pairing.UnpairAction
import dev.tandem.core.storage.trust.TrustStore

/** Hilt graph nodes [dev.tandem.app.MainActivity] builds its [AppShellDependencies] from. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface ShellEntryPoint {
    fun trustStore(): TrustStore

    fun connectionStatusViewModel(): ConnectionStatusViewModel

    fun connectionOrchestrator(): ConnectionOrchestrator

    fun unpairAction(): UnpairAction

    fun sessionRegistry(): SessionRegistry

    fun activeIdentityAlias(): ActiveIdentityAlias

    fun pairingFlow(): PairingFlow

    fun rotationComposition(): RotationComposition

    fun revokedNoticeStore(): RevokedNoticeStore

    fun rePairNoticeStore(): RePairNoticeStore
}
