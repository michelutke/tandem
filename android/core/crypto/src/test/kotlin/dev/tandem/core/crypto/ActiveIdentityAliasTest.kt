package dev.tandem.core.crypto

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class ActiveIdentityAliasTest {
    @Test
    fun nextAlias_defaultAlias_incrementsVersion() {
        assertEquals("tandem.identity.v2", ActiveIdentityAlias().nextAlias())
    }

    @Test
    fun nextAlias_afterActivate_incrementsFromActivated() {
        val alias = ActiveIdentityAlias()
        alias.activate("tandem.identity.v9")

        assertEquals("tandem.identity.v10", alias.nextAlias())
        assertEquals("tandem.identity.v9", alias.current)
    }

    @Test
    fun nextAlias_unversionedAlias_appendsV2() {
        assertEquals("custom.v2", ActiveIdentityAlias().apply { activate("custom") }.nextAlias())
    }

    @Test
    fun activeAlias_missingFile_defaultsToOriginalAlias(
        @TempDir dir: File,
    ) {
        assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(File(dir, "alias")).current)
    }

    @Test
    fun activeAlias_restartAfterActivate_readsActivatedAlias(
        @TempDir dir: File,
    ) {
        val file = File(dir, "alias")
        ActiveIdentityAlias(file).activate("tandem.identity.v2")

        assertEquals("tandem.identity.v2", ActiveIdentityAlias(file).current)
        assertEquals(listOf("alias"), dir.list()!!.toList())
    }

    @Test
    fun activeAlias_blankFile_defaultsToOriginalAlias(
        @TempDir dir: File,
    ) {
        val file = File(dir, "alias").apply { writeText("  \n") }

        assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(file).current)
    }
}
