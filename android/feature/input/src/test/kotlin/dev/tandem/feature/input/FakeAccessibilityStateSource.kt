package dev.tandem.feature.input

class FakeAccessibilityStateSource(
    var enabled: Boolean,
) : AccessibilityStateSource {
    override fun isServiceEnabled(): Boolean = enabled
}
