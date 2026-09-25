import Testing
@testable import TandemDesign

// Acceptance (E00-32): "DotProgress and DotRing expose VoiceOver values."

@Test func dotRing_value43_voiceOverValue43Percent() {
    #expect(DotRing.accessibilityValueText(value: 0.43) == "43%")
}

@Test func dotRing_value7of10_lightsSevenDots() {
    let ring = DotRing(value: 0.7, dotCount: 10)

    #expect(ring.litCount == 7)
}
