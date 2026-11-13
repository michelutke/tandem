import Testing
@testable import TandemDesign

@Test func sectionEmptyState_turnedOffMessages_titlePairNamesSectionAndDevice() {
    let kind = SectionEmptyState.Kind.turnedOffOnPhone(section: "Messages", deviceName: "Pixel 9")

    #expect(kind.subject == "Messages.")
    #expect(kind.stateText == "Turned off on the phone. Enable Messages in Tandem on Pixel 9.")
}

@Test func sectionEmptyState_photosNoAccess_titlePairNamesDevice() {
    let kind = SectionEmptyState.Kind.noAccess(section: "Photos", deviceName: "Pixel 9")

    #expect(kind.subject == "Photos.")
    #expect(kind.stateText == "Pixel 9 hasn't shared photos. Allow access in Tandem on the phone.")
}

@Test func sectionEmptyState_offline_titlePairShowsLastSeen() {
    let kind = SectionEmptyState.Kind.offline(lastSeenText: "14:02")

    #expect(kind.subject == "Offline.")
    #expect(kind.stateText == "Seen 14:02")
}
