package dev.tandem.core.crypto.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.tandem.core.crypto.ActiveIdentityAlias
import java.io.File
import javax.inject.Singleton

private const val ACTIVE_ALIAS_FILE_NAME = "active_identity_alias"

// Downstream epics (e.g. E10-15 IdentityKeyStore) add further @Binds/@Provides bindings here.
@Module
@InstallIn(SingletonComponent::class)
object CryptoHiltModule {
    @Provides
    @Singleton
    fun provideActiveIdentityAlias(
        @ApplicationContext context: Context,
    ): ActiveIdentityAlias = ActiveIdentityAlias(File(context.filesDir, ACTIVE_ALIAS_FILE_NAME))
}
