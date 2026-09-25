package dev.tandem.app.di

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File
import java.net.URL
import java.net.URLDecoder
import java.util.Collections
import java.util.jar.JarEntry
import java.util.jar.JarFile

// unit (E00-03): coreHiltModules_classpathScan_exactlyOneEmptyModulePerCoreModule.
// Scans each core/* module's compiled `di` package on `:app`'s test classpath for classes wired
// into the SingletonComponent via `@Module @InstallIn`, so a stray second module (or one that
// quietly grows bindings) fails here instead of surfacing later at Hilt-aggregation time.
//
// `@Module`/`@InstallIn` use `RetentionPolicy.CLASS` (verified against the resolved
// `hilt-core:2.60.1` classfile), so they are invisible to runtime reflection
// (`Class.getAnnotation`) and can't be scanned that way. Instead this scans the
// `hilt_aggregated_deps` package: Hilt's own annotation processor writes one marker class there
// per `@Module @InstallIn` it processes, named `_<module's FQCN with dots replaced by
// underscores>` -- the same mechanism the real `:app` Hilt component aggregation task relies on
// to discover modules across the classpath, so a class without a marker was never aggregated.
class CoreHiltModulesTest {
    private val coreDiPackages =
        listOf(
            "dev.tandem.core.crypto.di",
            "dev.tandem.core.pairing.di",
            "dev.tandem.core.protocol.di",
            "dev.tandem.core.storage.di",
            "dev.tandem.core.transport.di",
        )

    @Test
    fun coreHiltModules_classpathScan_exactlyOneEmptyModulePerCoreModule() {
        coreDiPackages.forEach { packageName ->
            val hiltModules = classesInPackage(packageName).filter { it.hasHiltAggregatedDepsMarker() }

            assertEquals(1, hiltModules.size, "expected exactly one Hilt module in $packageName, found $hiltModules")
            assertEquals(
                0,
                hiltModules.single().declaredMethods.size,
                "expected zero bindings in ${hiltModules.single()}",
            )
        }
    }

    private fun Class<*>.hasHiltAggregatedDepsMarker(): Boolean {
        val markerName = "hilt_aggregated_deps._${name.replace('.', '_')}"
        return runCatching { Class.forName(markerName, false, classLoader) }.isSuccess
    }

    private fun classesInPackage(packageName: String): List<Class<*>> {
        val packagePath = packageName.replace('.', '/')
        val classLoader = checkNotNull(Thread.currentThread().contextClassLoader)
        val classNames = sortedSetOf<String>()

        val resources = Collections.list(classLoader.getResources(packagePath))
        for (resource in resources) {
            classNames += classNamesAt(resource, packageName, packagePath)
        }

        return classNames.map { classLoader.loadClass(it) }
    }

    private fun classNamesAt(
        resource: URL,
        packageName: String,
        packagePath: String,
    ): List<String> =
        when (resource.protocol) {
            "file" -> classNamesInDirectory(resource, packageName)
            "jar" -> classNamesInJar(resource, packageName, packagePath)
            else -> emptyList()
        }

    private fun classNamesInDirectory(
        resource: URL,
        packageName: String,
    ): List<String> {
        val classFiles = File(resource.toURI()).listFiles { file -> file.isFile && file.extension == "class" }
        val names = mutableListOf<String>()
        classFiles?.forEach { names += "$packageName.${it.nameWithoutExtension}" }
        return names
    }

    private fun classNamesInJar(
        resource: URL,
        packageName: String,
        packagePath: String,
    ): List<String> {
        val entryPrefix = "$packagePath/"
        val jarUrl = resource.path.substringAfter("file:").substringBefore("!")
        val jarPath = URLDecoder.decode(jarUrl, "UTF-8")
        val names = mutableListOf<String>()

        JarFile(jarPath).use { jar ->
            val entries = Collections.list(jar.entries())
            for (entry in entries) {
                if (isClassEntryDirectlyIn(entry, entryPrefix)) {
                    val simpleName = entry.name.removePrefix(entryPrefix).removeSuffix(".class")
                    names += "$packageName.$simpleName"
                }
            }
        }

        return names
    }

    private fun isClassEntryDirectlyIn(
        entry: JarEntry,
        entryPrefix: String,
    ): Boolean =
        entry.name.startsWith(entryPrefix) &&
            entry.name.endsWith(".class") &&
            entry.name.indexOf('/', entryPrefix.length) == -1
}
