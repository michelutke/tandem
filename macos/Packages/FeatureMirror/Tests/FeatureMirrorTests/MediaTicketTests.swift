import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemTestSupport
@testable import FeatureMirror

private let sessionA = MediaSessionID(rawValue: UUID())
private let sessionB = MediaSessionID(rawValue: UUID())
private let peerA = fingerprint(0xA1)
private let peerB = fingerprint(0xB2)

private func fingerprint(_ byte: UInt8) -> SpkiFingerprint {
    // swiftlint:disable:next force_try
    try! SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
}

private final class SequentialTicketSource: MediaTicketSource {
    private let next = Mutex<UInt8>(1)

    func generateTicket() -> Data {
        let value = next.withLock { current -> UInt8 in
            defer { current += 1 }
            return current
        }
        return Data(repeating: value, count: MediaTicketTable<ManualTestClock>.ticketByteCount)
    }
}

private final class ComparisonSpy: Sendable {
    private let calls = Mutex(0)

    var callCount: Int { calls.withLock { $0 } }

    var comparator: MediaTicketComparator {
        { [self] lhs, rhs in
            calls.withLock { $0 += 1 }
            return constantTimeEquals(lhs, rhs)
        }
    }
}

private struct Harness {
    let clock = ManualTestClock()
    let table: MediaTicketTable<ManualTestClock>
    let issuer: MediaTicketIssuer<ManualTestClock>
    let validator: MediaTicketValidator<ManualTestClock>

    init(
        source: MediaTicketSource = SequentialTicketSource(),
        comparator: @escaping MediaTicketComparator = constantTimeEquals
    ) {
        let epoch = Date(timeIntervalSince1970: 1_000)
        let dates = FixedDateProvider(clock: clock, epoch: epoch)
        table = MediaTicketTable(clock: clock, comparator: comparator)
        issuer = MediaTicketIssuer(table: table, source: source, dateProvider: dates.provider)
        validator = MediaTicketValidator(table: table)
    }

    func validationError(_ ticket: Data?, peer: SpkiFingerprint) -> MediaTicketError? {
        do {
            _ = try validator.validate(ticket: ticket, presentingSpki: peer)
            return nil
        } catch {
            return error
        }
    }
}

@Test func mediaTicketIssuer_issue_returns32ByteTicketExpiringIn30s() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)

    #expect(issued.ticket.count == 32)
    #expect(issued.expiresAtMillis == 1_000_000 + 30_000)
}

@Test func mediaTicketIssuer_issueTwice_returnsDistinctTickets() {
    let harness = Harness()
    let first = harness.issuer.issue(session: sessionA, peer: peerA)
    let second = harness.issuer.issue(session: sessionB, peer: peerB)

    #expect(first.ticket != second.ticket)
}

@Test func systemMediaTicketSource_generateTicket_returns32DistinctRandomBytes() {
    let source = SystemMediaTicketSource()
    let first = source.generateTicket()
    let second = source.generateTicket()

    #expect(first.count == 32)
    #expect(first != second)
}

@Test func mediaTicketValidator_validUnusedTicketWithin30s_returnsIssuingSession() throws {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.clock.advance(by: .seconds(29))

    let session = try harness.validator.validate(ticket: issued.ticket, presentingSpki: peerA)

    #expect(session == sessionA)
}

@Test func mediaTicketValidator_clockAdvanced30s_returnsExpired() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.clock.advance(by: .seconds(30))

    #expect(harness.validationError(issued.ticket, peer: peerA) == .expired)
}

@Test func mediaTicketValidator_presentedAt31s_returnsExpired() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.clock.advance(by: .seconds(31))

    #expect(harness.validationError(issued.ticket, peer: peerA) == .expired)
}

@Test func mediaTicketValidator_presentedAt61s_returnsUnknownOncePurged() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.clock.advance(by: .seconds(61))

    #expect(harness.validationError(issued.ticket, peer: peerA) == .unknown)
}

@Test func mediaTicketTable_overCap_dropsOldestRecords() {
    let harness = Harness()
    let first = harness.issuer.issue(session: sessionA, peer: peerA)
    for _ in 0..<MediaTicketTable<ManualTestClock>.maxRecords {
        _ = harness.issuer.issue(session: sessionB, peer: peerA)
    }

    #expect(harness.validationError(first.ticket, peer: peerA) == .unknown)
}

@Test func mediaTicketValidator_secondPresentation_returnsConsumed() throws {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    _ = try harness.validator.validate(ticket: issued.ticket, presentingSpki: peerA)

    #expect(harness.validationError(issued.ticket, peer: peerA) == .consumed)
}

@Test func mediaTicketValidator_absentOrWrongLengthTicket_returnsMissing() {
    let harness = Harness()
    _ = harness.issuer.issue(session: sessionA, peer: peerA)

    #expect(harness.validationError(nil, peer: peerA) == .missing)
    #expect(harness.validationError(Data(), peer: peerA) == .missing)
    #expect(harness.validationError(Data(repeating: 1, count: 31), peer: peerA) == .missing)
    #expect(harness.validationError(Data(repeating: 1, count: 33), peer: peerA) == .missing)
}

@Test func mediaTicketValidator_unrecognizedTicket_returnsUnknownAndDoesNotBurnRealTicket() throws {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)

    #expect(harness.validationError(Data(repeating: 0xEE, count: 32), peer: peerA) == .unknown)
    #expect(try harness.validator.validate(ticket: issued.ticket, presentingSpki: peerA) == sessionA)
}

@Test func mediaTicketValidator_presentingSpkiDiffersFromIssuer_returnsPeerMismatch() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)

    #expect(harness.validationError(issued.ticket, peer: peerB) == .peerMismatch)
}

@Test func mediaTicketValidator_afterPeerMismatch_ticketUnusableByIssuingPeer() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    _ = harness.validationError(issued.ticket, peer: peerB)

    #expect(harness.validationError(issued.ticket, peer: peerA) == .consumed)
}

@Test func mediaTicketValidator_ticketFromSessionAOnPeerBConnection_neverReturnsSessionA() {
    let harness = Harness()
    let issuedA = harness.issuer.issue(session: sessionA, peer: peerA)
    _ = harness.issuer.issue(session: sessionB, peer: peerB)

    #expect(harness.validationError(issuedA.ticket, peer: peerB) == .peerMismatch)
}

@Test func mediaTicketValidator_issuingSessionEnded_returnsRevoked() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.issuer.sessionEnded(sessionA)

    #expect(harness.validationError(issued.ticket, peer: peerA) == .revoked)
}

@Test func mediaTicketValidator_sessionEndedThenPeerMismatch_returnsPeerMismatchFirst() {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.issuer.sessionEnded(sessionA)

    #expect(harness.validationError(issued.ticket, peer: peerB) == .peerMismatch)
}

@Test func mediaTicketIssuer_secondIssueSameSession_supersedesFirstAsConsumed() throws {
    let harness = Harness()
    let first = harness.issuer.issue(session: sessionA, peer: peerA)
    let second = harness.issuer.issue(session: sessionA, peer: peerA)

    #expect(harness.validationError(first.ticket, peer: peerA) == .consumed)
    #expect(try harness.validator.validate(ticket: second.ticket, presentingSpki: peerA) == sessionA)
}

@Test func mediaTicketValidator_ticketComparison_usesConstantTimeHelper() {
    let spy = ComparisonSpy()
    let harness = Harness(comparator: spy.comparator)
    _ = harness.issuer.issue(session: sessionA, peer: peerA)
    let second = harness.issuer.issue(session: sessionB, peer: peerB)
    _ = harness.issuer.issue(session: sessionB, peer: peerB)

    _ = harness.validationError(second.ticket, peer: peerB)

    #expect(spy.callCount == 3)
}

@Test func mediaTicketValidator_wrongLengthTicket_comparesNothing() {
    let spy = ComparisonSpy()
    let harness = Harness(comparator: spy.comparator)
    _ = harness.issuer.issue(session: sessionA, peer: peerA)

    _ = harness.validationError(Data(repeating: 1, count: 31), peer: peerA)

    #expect(spy.callCount == 0)
}

@Test func mediaTicketIssuer_issueAndValidate_ticketBytesNeverLogged() throws {
    let harness = Harness()
    let issued = harness.issuer.issue(session: sessionA, peer: peerA)
    let hex = issued.ticket.map { String(format: "%02x", $0) }.joined()
    let base64 = issued.ticket.base64EncodedString()
    var outputs = [String(describing: issued), String(reflecting: issued)]
    _ = try harness.validator.validate(ticket: issued.ticket, presentingSpki: peerA)
    do {
        _ = try harness.validator.validate(ticket: issued.ticket, presentingSpki: peerA)
    } catch {
        outputs.append(String(describing: error))
        outputs.append(String(reflecting: error))
    }
    outputs.append(String(describing: harness.table))

    for output in outputs {
        #expect(!output.lowercased().contains(hex))
        #expect(!output.contains(base64))
    }
}

@Test func mediaTicketValidatorAdapter_eachRejection_reportsItsOwnReason() throws {
    let harness = Harness()
    let adapter = MediaTicketValidatorAdapter(validator: harness.validator)
    let consumed = harness.issuer.issue(session: sessionA, peer: peerA)
    let mismatched = harness.issuer.issue(session: sessionB, peer: peerB)
    _ = try harness.validator.validate(ticket: consumed.ticket, presentingSpki: peerA)

    #expect(adapter.validate(ticket: nil, presentingSpki: peerA) == .failure(.missing))
    #expect(adapter.validate(ticket: consumed.ticket, presentingSpki: peerA) == .failure(.consumed))
    #expect(adapter.validate(ticket: mismatched.ticket, presentingSpki: peerA) == .failure(.peerMismatch))

    let revoked = harness.issuer.issue(session: sessionA, peer: peerA)
    harness.table.endSession(sessionA)
    #expect(adapter.validate(ticket: revoked.ticket, presentingSpki: peerA) == .failure(.revoked))

    let expiring = harness.issuer.issue(session: sessionB, peer: peerB)
    harness.clock.advance(by: .seconds(30))
    #expect(adapter.validate(ticket: expiring.ticket, presentingSpki: peerB) == .failure(.expired))
}
