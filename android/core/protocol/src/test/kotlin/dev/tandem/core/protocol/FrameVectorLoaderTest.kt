package dev.tandem.core.protocol

import kotlinx.serialization.json.jsonArray
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * E11-11: proves `loadVectorsFile` discovers fixtures at runtime from whatever the manifest on
 * disk holds, rather than any count or id list hard-coded in test code — the acceptance criterion
 * a fixture added to the manifest increases the executed case count by one without a code change.
 */
class FrameVectorLoaderTest {
    @Test
    fun frameVectorLoader_extraFixtureInDirectory_discoveredWithoutCodeChange(
        @TempDir tempDir: File,
    ) {
        writeManifest(tempDir, vectorCount = 2)
        val countBeforeFixtureAdded = loadVectorsFile(tempDir).getValue("vectors").jsonArray.size

        writeManifest(tempDir, vectorCount = 3)
        val countAfterFixtureAdded = loadVectorsFile(tempDir).getValue("vectors").jsonArray.size

        assertEquals(countBeforeFixtureAdded + 1, countAfterFixtureAdded)
    }

    private fun writeManifest(
        dir: File,
        vectorCount: Int,
    ) {
        val vectors =
            (1..vectorCount).joinToString(separator = ",") { index ->
                """{"id":"synthetic-$index","description":"synthetic fixture $index","input":{},"expected":{}}"""
            }
        File(dir, "frame-encoding.json").writeText(
            """{"category":"frame-encoding","generatedBy":"tools/vectors/generate.py","vectors":[$vectors]}""",
        )
    }
}
