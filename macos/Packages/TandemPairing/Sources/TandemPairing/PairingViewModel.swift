import CoreImage
import Foundation
import TandemCrypto

/// The Mac's pairing QR screen (E14-11, `docs/protocol/SPEC.md` § Pairing window): renders the
/// current window's payload as a QR code with a visible 120 s countdown, auto-regenerating a
/// fresh code and secret the moment a window expires outright, and surfacing an explicit
/// "Regenerate" action once its attempt budget is exhausted (`docs/protocol/SPEC.md`
/// "Pairing-window DoS trade-off": "recovered by regenerating the QR").
///
/// Presentation-independent -- no `SwiftUI`/`AppKit` import -- so it's unit-testable against a
/// real ``PairingWindow`` the same way ``PairConfirmationViewModel`` is; ``PairingView`` is its
/// (untested) SwiftUI presentation. Time is re-settled lazily on every read, matching
/// ``PairingWindow``'s own idiom -- there is no background `Task`/timer here either; ``tick()`` is
/// called once per UI-driven countdown tick (real time in production, a `ManualTestClock` advance
/// in tests) and is the only place this type ever mutates anything.
public final class PairingViewModel: @unchecked Sendable {
    /// Copy for the attempts-exhausted screen (E14-11 acceptance); the same text regardless of
    /// which of the window's failure reasons burned the last attempt (`docs/protocol/SPEC.md` §
    /// `PAIRING_FAILED`: "text MUST NOT distinguish which of the five local reasons occurred").
    public static let attemptsExhaustedMessage =
        "Pairing attempts used up. Someone else may be trying to pair. Generate a new code."

    private let window: PairingWindow
    private let fingerprint: SpkiFingerprint
    private let secretSource: any SecretSource
    private let addressSource: any LocalAddressSource
    private let port: Int
    private let name: String
    private let dateProvider: DateProvider
    private let regeneratesOnExpiry: Bool

    private let lock = NSLock()
    private var payload: QrPayload

    /// Opens `window` with a freshly generated payload (E14-01) as a side effect of
    /// initialization -- there is no separate "start" call.
    public init(
        window: PairingWindow,
        fingerprint: SpkiFingerprint,
        secretSource: any SecretSource,
        addressSource: any LocalAddressSource,
        port: Int,
        name: String,
        dateProvider: @escaping DateProvider,
        regeneratesOnExpiry: Bool = true
    ) {
        self.window = window
        self.fingerprint = fingerprint
        self.secretSource = secretSource
        self.addressSource = addressSource
        self.port = port
        self.name = name
        self.dateProvider = dateProvider
        self.regeneratesOnExpiry = regeneratesOnExpiry
        let payload = QrPayloadEncoder.generate(
            fingerprint: fingerprint,
            secretSource: secretSource,
            addressSource: addressSource,
            port: port,
            name: name
        )
        self.payload = payload
        window.open(secret: payload.secret)
    }

    /// The current window's payload. Never logged -- `QrPayload`'s own `description`/
    /// `debugDescription` are redacted, so an accidental interpolation of this can't leak it.
    public var currentPayload: QrPayload {
        lock.lock()
        defer { lock.unlock() }
        return payload
    }

    /// `true` while the window was opened in manual mode: the screen shows this Mac's address for the
    /// phone to enter instead of a QR code, and no QR payload is ever rendered (ADR-008).
    public var isManual: Bool {
        window.mode == .manual
    }

    /// `address:port` of this Mac's first routable address for the owner to type on the phone (IPv6
    /// bracketed); `nil` if no routable address exists. Never a trust anchor, only a place to dial.
    public var manualAddressText: String? {
        guard let address = QrPayloadEncoder.routableAddresses(from: addressSource.currentAddresses()).first else {
            return nil
        }
        return address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    /// `CIQRCodeGenerator` output for ``currentPayload``'s URI (E14-11 acceptance: decodes via
    /// `CIDetector` to exactly this payload). `nil` only if Core Image itself fails.
    public var qrImage: CIImage? {
        guard !isManual else { return nil }
        return QrCodeImage.generate(message: currentPayload.uri)
    }

    /// ``qrImage``'s module grid, ready for ``DotQR``. Empty if ``qrImage`` is `nil`.
    public var qrModules: [[Bool]] {
        qrImage.map(QrCodeImage.modules(for:)) ?? []
    }

    /// Seconds left in the current window; `0` once it has closed for any reason (expired,
    /// attempts exhausted, or otherwise).
    public var remainingSeconds: Int {
        guard let expiresAt = window.expiresAt else { return 0 }
        return max(0, Int(expiresAt.timeIntervalSince(dateProvider()).rounded(.up)))
    }

    /// Attempts left in the current (or just-closed) window.
    public var attemptsRemaining: Int {
        window.attemptsRemaining
    }

    /// `true` once the window's 3-attempt budget is exhausted -- the one case ``tick()`` never
    /// auto-regenerates; the owner must click "Regenerate".
    public var attemptsExhausted: Bool {
        window.closedReason == .attemptsExhausted
    }

    /// Re-settles ``PairingWindow``'s own lazily-settled expiry and, only for a plain 120 s
    /// timeout, opens a fresh window with a new secret and restarts the countdown -- a no-op once
    /// attempts are exhausted (``regenerate()`` is manual there) or while still open. Call once
    /// per UI-visible countdown tick.
    public func tick() {
        guard regeneratesOnExpiry, window.closedReason == .expired else { return }
        regenerate()
    }

    /// Opens a fresh window with a new secret and payload, invalidating the previous one --
    /// called automatically by ``tick()`` on plain expiry, and by the owner's "Regenerate" action
    /// once attempts are exhausted.
    public func regenerate() {
        guard !isManual else {
            window.openManual()
            return
        }
        let newPayload = QrPayloadEncoder.generate(
            fingerprint: fingerprint,
            secretSource: secretSource,
            addressSource: addressSource,
            port: port,
            name: name
        )
        window.open(secret: newPayload.secret)
        lock.lock()
        payload = newPayload
        lock.unlock()
    }
}
