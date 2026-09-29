import Foundation
import Testing
@testable import TandemProtocol

/// ContactThumbnailValidator tests (E51-01): the CONTACTS channel's `photo_thumbnail` byte cap
/// (`docs/protocol/SPEC.md` `#contacts-channel` "Thumbnail cap"), 32,768 bytes (32 KiB).
struct ContactThumbnailValidatorTests {
    @Test
    func macContactThumbnailValidator_emptyThumbnail_isValid() {
        #expect(ContactThumbnailValidator.isValid(Data()))
    }

    @Test
    func macContactThumbnailValidator_exactly32768Bytes_isValid() {
        let thumbnail = Data(repeating: 0, count: ContactThumbnailValidator.maxPhotoThumbnailBytes)
        #expect(ContactThumbnailValidator.isValid(thumbnail))
    }

    @Test
    func macContactThumbnailValidator_oneByteOver32768_isRejected() {
        let thumbnail = Data(repeating: 0, count: ContactThumbnailValidator.maxPhotoThumbnailBytes + 1)
        #expect(!ContactThumbnailValidator.isValid(thumbnail))
    }

    @Test
    func macContactThumbnailValidator_wellOverCap_isRejected() {
        let thumbnail = Data(repeating: 0, count: 1_000_000)
        #expect(!ContactThumbnailValidator.isValid(thumbnail))
    }
}
