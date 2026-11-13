package dev.tandem.app.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.connection.IdentityBootstrap
import dev.tandem.app.connection.RePairNoticeStore
import dev.tandem.app.connection.RevokedNoticeStore
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.AndroidKeyStoreIdentityKeyStore
import dev.tandem.core.crypto.IdentityBootstrapper
import dev.tandem.core.storage.trust.TrustStore
import java.io.File
import javax.inject.Singleton

private const val ACTIVE_ALIAS_FILE_NAME = "active_identity_alias"
private const val RE_PAIR_NOTICE_FILE_NAME = "identity_reset_notice"
private const val REVOKED_NOTICE_FILE_NAME = "revoked_by_peer_notice"

// App-level identity bindings; core/* Hilt modules stay empty (CoreHiltModulesTest).
@Module
@InstallIn(SingletonComponent::class)
object IdentityModule {
    @Provides
    @Singleton
    fun provideActiveIdentityAlias(
        @ApplicationContext context: Context,
    ): ActiveIdentityAlias = ActiveIdentityAlias(File(context.filesDir, ACTIVE_ALIAS_FILE_NAME))

    @Provides
    @Singleton
    fun provideRePairNoticeStore(
        @ApplicationContext context: Context,
    ): RePairNoticeStore = RePairNoticeStore(File(context.filesDir, RE_PAIR_NOTICE_FILE_NAME))

    @Provides
    @Singleton
    fun provideRevokedNoticeStore(
        @ApplicationContext context: Context,
    ): RevokedNoticeStore = RevokedNoticeStore(File(context.filesDir, REVOKED_NOTICE_FILE_NAME))

    @Provides
    @Singleton
    fun provideIdentityBootstrap(
        activeIdentityAlias: ActiveIdentityAlias,
        trustStore: TrustStore,
        rePairNotice: RePairNoticeStore,
    ): IdentityBootstrap =
        IdentityBootstrap(
            bootstrap = {
                IdentityBootstrapper(
                    AndroidKeyStoreIdentityKeyStore(AppClock.system),
                    activeIdentityAlias,
                    onIdentityReset = rePairNotice::require,
                ).bootstrapIdentity(hasPairedPeers = trustStore.list().isNotEmpty())
            },
            dispatcher = AppDispatchers.io,
        )
}
