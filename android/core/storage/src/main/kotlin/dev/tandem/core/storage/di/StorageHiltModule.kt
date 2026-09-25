package dev.tandem.core.storage.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

// Empty Hilt module shell (E00-03): downstream epics add @Binds/@Provides bindings here instead
// of wiring a new Dagger component from scratch. No production bindings yet.
@Module
@InstallIn(SingletonComponent::class)
object StorageHiltModule
