package dev.tandem.app.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.tandem.app.connection.IdentityBootstrap
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.AndroidKeyStoreIdentityKeyStore
import dev.tandem.core.crypto.IdentityBootstrapper
import java.io.File
import javax.inject.Singleton

private const val ACTIVE_ALIAS_FILE_NAME = "active_identity_alias"

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
    fun provideIdentityBootstrap(activeIdentityAlias: ActiveIdentityAlias): IdentityBootstrap =
        IdentityBootstrap(
            bootstrap = {
                IdentityBootstrapper(AndroidKeyStoreIdentityKeyStore(AppClock.system), activeIdentityAlias)
                    .bootstrapIdentity()
            },
            dispatcher = AppDispatchers.io,
        )
}
