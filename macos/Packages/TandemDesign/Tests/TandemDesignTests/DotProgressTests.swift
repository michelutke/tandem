import Testing
@testable import TandemDesign

// tdd (E00-32): ui: dotProgress_value43_voiceOverValue43Percent

@Test func dotProgress_value43_voiceOverValue43Percent() {
    #expect(DotProgress.accessibilityValueText(value: 0.43) == "43%")
}

@Test func dotProgress_value0_voiceOverValue0Percent() {
    #expect(DotProgress.accessibilityValueText(value: 0) == "0%")
}

@Test func dotProgress_value1_voiceOverValue100Percent() {
    #expect(DotProgress.accessibilityValueText(value: 1) == "100%")
}

@Test func dotProgress_valueAboveOne_clampsTo100Percent() {
    #expect(DotProgress.accessibilityValueText(value: 1.5) == "100%")
}

@Test func dotProgress_valueBelowZero_clampsTo0Percent() {
    #expect(DotProgress.accessibilityValueText(value: -0.2) == "0%")
}

@Test func dotProgress_value43of10Dots_lightsFourDots() {
    let progress = DotProgress(value: 0.43, dotCount: 10)

    #expect(progress.litCount == 4)
}
