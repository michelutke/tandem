import Foundation
import Testing

@testable import TandemApp

@Suite("ReceivedFileNotificationCopy")
struct ReceivedFileNotificationCopyTests {
    private let home = "/Users/ada"

    @Test
    func receivedFileCopy_title_isFileNameThenReceived() {
        #expect(ReceivedFileNotificationCopy.title(displayName: "holiday-2026.mov") == "holiday-2026.mov received")
    }

    @Test
    func receivedFileCopy_sizeKnownInsideHome_bodyShowsSizeAndHomeRelativeFolder() {
        let destination = URL(fileURLWithPath: "/Users/ada/Downloads/Tandem/holiday-2026.mov")

        let body = ReceivedFileNotificationCopy.body(size: 2_800_000_000, destination: destination, home: home)

        #expect(body.hasSuffix(" · saved to Downloads/Tandem"))
        #expect(body.contains("GB"))
    }

    @Test
    func receivedFileCopy_sizeUnknown_bodyIsSavedToFolderOnly() {
        let destination = URL(fileURLWithPath: "/Users/ada/Downloads/Tandem/scan.pdf")

        let body = ReceivedFileNotificationCopy.body(size: nil, destination: destination, home: home)

        #expect(body == "Saved to Downloads/Tandem")
    }

    @Test
    func receivedFileCopy_folderOutsideHome_bodyShowsFullFolderPath() {
        let destination = URL(fileURLWithPath: "/Volumes/Share/Inbox/scan.pdf")

        let body = ReceivedFileNotificationCopy.body(size: nil, destination: destination, home: home)

        #expect(body == "Saved to /Volumes/Share/Inbox")
    }
}
