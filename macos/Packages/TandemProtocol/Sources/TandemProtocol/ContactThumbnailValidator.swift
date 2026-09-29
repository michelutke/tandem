import Foundation

/// Validates a `Contact.photo_thumbnail`'s byte length against the CONTACTS channel's cap
/// (`docs/protocol/SPEC.md` `#contacts-channel` "Thumbnail cap", E51-01): a JPEG no larger than
/// 96 px on its longest edge and no larger than 32,768 bytes (32 KiB). The cap is enforced here in
/// bytes only -- a receiver decodes `photo_thumbnail` as an opaque `bytes` field and cannot itself
/// check the JPEG's decoded pixel dimensions, only its encoded byte length
/// (`docs/planning/backlog/phase-5.yaml` E51-01 notes); the pixel-dimension rule is enforced by
/// the sender's own thumbnail-generation step, not by this validator.
///
/// A `photo_thumbnail` over the cap MUST be rejected before it is ever displayed or persisted --
/// never silently truncated or accepted oversized. Mirrors the Android
/// `dev.tandem.core.protocol.ContactThumbnailValidator` (E51-01).
public enum ContactThumbnailValidator {
    /// CONTACTS channel's `photo_thumbnail` cap (`docs/protocol/SPEC.md` `#contacts-channel`
    /// "Thumbnail cap"): 32 KiB, 2^15.
    public static let maxPhotoThumbnailBytes = 32_768

    /// `true` if `photoThumbnail` is within the 32,768-byte cap (including an empty/absent
    /// thumbnail); `false` if it MUST be rejected.
    public static func isValid(_ photoThumbnail: Data) -> Bool {
        photoThumbnail.count <= maxPhotoThumbnailBytes
    }
}
