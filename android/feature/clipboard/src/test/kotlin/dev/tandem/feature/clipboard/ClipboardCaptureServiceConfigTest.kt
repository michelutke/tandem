package dev.tandem.feature.clipboard

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.w3c.dom.Document
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/** ADR-007 / D-82 `ci:` tests: the copy detector stays minimal. Reads checked-in sources. Plain JUnit5. */
class ClipboardCaptureServiceConfigTest {
    private val androidNs = "http://schemas.android.com/apk/res/android"

    private fun parse(path: String): Document =
        DocumentBuilderFactory
            .newInstance()
            .apply { isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(File(path))

    @Test
    fun clipboardCaptureServiceConfig_declaredAttributes_areExactlyTheMinimalSet() {
        val element = parse("src/main/res/xml/clipboard_capture_service.xml").documentElement
        val attributes =
            (0 until element.attributes.length)
                .map { element.attributes.item(it) }
                .filter { it.namespaceURI == androidNs }
                .associate { it.localName to it.nodeValue }

        assertEquals(
            mapOf(
                "accessibilityEventTypes" to "typeWindowStateChanged",
                "accessibilityFeedbackType" to "feedbackGeneric",
                "canRetrieveWindowContent" to "false",
                "packageNames" to "com.android.systemui",
                "description" to "@string/clipboard_capture_service_description",
            ),
            attributes,
        )
    }

    @Test
    fun mergedManifest_clipboardCaptureService_requiresBindAccessibilityPermission() {
        val services = parse("src/main/AndroidManifest.xml").getElementsByTagName("service")
        val service =
            (0 until services.length)
                .map { services.item(it) as Element }
                .single { it.getAttributeNS(androidNs, "name").endsWith("ClipboardCaptureService") }

        assertEquals("android.permission.BIND_ACCESSIBILITY_SERVICE", service.getAttributeNS(androidNs, "permission"))
    }

    @Test
    fun accessibilityServices_labels_existAndDiffer() {
        val clipboardLabel = serviceLabel("src/main/AndroidManifest.xml", "ClipboardCaptureService")
        val inputLabel = serviceLabel("../input/src/main/AndroidManifest.xml", "TandemAccessibilityService")

        assertNotEquals(clipboardLabel, inputLabel)
        assertEquals("Tandem clipboard", stringValue("src/main/res/values/strings.xml", clipboardLabel))
        assertEquals("Tandem remote control", stringValue("../input/src/main/res/values/strings.xml", inputLabel))
    }

    private fun serviceLabel(
        manifestPath: String,
        serviceName: String,
    ): String {
        val services = parse(manifestPath).getElementsByTagName("service")
        val service =
            (0 until services.length)
                .map { services.item(it) as Element }
                .single { it.getAttributeNS(androidNs, "name").endsWith(serviceName) }
        return service
            .getAttributeNS(androidNs, "label")
            .also {
                assertTrue(it.startsWith("@string/"))
            }.removePrefix("@string/")
    }

    private fun stringValue(
        path: String,
        name: String,
    ): String {
        val strings = parse(path).getElementsByTagName("string")
        return (0 until strings.length)
            .map { strings.item(it) as Element }
            .single { it.getAttribute("name") == name }
            .textContent
    }
}
