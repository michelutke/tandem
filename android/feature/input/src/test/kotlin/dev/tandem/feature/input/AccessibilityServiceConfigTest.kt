package dev.tandem.feature.input

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.w3c.dom.Document
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/** E62-02 `ci:` tests; read the checked-in config and manifest sources directly. Plain JUnit5. */
class AccessibilityServiceConfigTest {
    private val androidNs = "http://schemas.android.com/apk/res/android"

    private fun parse(path: String): Document {
        val builder = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }.newDocumentBuilder()
        return builder.parse(File(path))
    }

    private fun configAttributes(): Map<String, String> {
        val element = parse("src/main/res/xml/tandem_accessibility_service.xml").documentElement
        return (0 until element.attributes.length)
            .map { element.attributes.item(it) }
            .filter { it.namespaceURI == androidNs }
            .associate { it.localName to it.nodeValue }
    }

    @Test
    fun accessibilityServiceConfig_declaredCapabilities_equalAllowlist() {
        val allowlist =
            File("accessibility-service-config.allowlist")
                .readLines()
                .filter { it.isNotBlank() && !it.startsWith("#") }
                .associate { line -> line.trim().split("=", limit = 2).let { it[0] to it[1] } }

        assertEquals(allowlist, configAttributes().filterKeys { it != "description" })
    }

    @Test
    fun accessibilityServiceConfig_flags_omitKeyEventFilteringAndInputMethodEditor() {
        val flags = configAttributes()["accessibilityFlags"].orEmpty()

        assertFalse(flags.contains("flagRequestFilterKeyEvents"))
        assertFalse(flags.contains("flagInputMethodEditor"))
    }

    @Test
    fun mergedManifest_accessibilityService_requiresBindAccessibilityPermission() {
        val services = parse("src/main/AndroidManifest.xml").getElementsByTagName("service")
        val service =
            (0 until services.length)
                .map { services.item(it) as Element }
                .single { it.getAttributeNS(androidNs, "name").endsWith("TandemAccessibilityService") }

        assertEquals("android.permission.BIND_ACCESSIBILITY_SERVICE", service.getAttributeNS(androidNs, "permission"))
    }
}
