import Foundation
import TandemCrypto
import TandemTransport

/// Adapts ``MediaTicketValidator`` to the media acceptor's ``MediaTicketValidating`` seam, mapping
/// the local errors as `MediaTicketError` documents.
public struct MediaTicketValidatorAdapter<C: Clock<Duration> & Sendable>: MediaTicketValidating {
    private let validator: MediaTicketValidator<C>

    public init(validator: MediaTicketValidator<C>) {
        self.validator = validator
    }

    public func validate(ticket: Data?, presentingSpki: SpkiFingerprint) -> Result<UUID, MediaTicketRejectReason> {
        do {
            return .success(try validator.validate(ticket: ticket, presentingSpki: presentingSpki).rawValue)
        } catch {
            switch error {
            case .missing: return .failure(.missing)
            case .unknown, .consumed: return .failure(.consumed)
            case .expired: return .failure(.expired)
            case .revoked: return .failure(.revoked)
            case .peerMismatch: return .failure(.peerMismatch)
            }
        }
    }
}
