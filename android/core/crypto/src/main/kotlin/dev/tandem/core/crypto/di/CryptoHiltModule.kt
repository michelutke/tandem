package dev.tandem.core.crypto.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

// Empty Hilt module shell (E00-03): downstream epics (e.g. E10-15 IdentityKeyStore) add
// @Binds/@Provides bindings here instead of wiring a new Dagger component from scratch.
// No production bindings yet.
@Module
@InstallIn(SingletonComponent::class)
object CryptoHiltModule
