import Foundation
import os
import Synchronization
import TandemCrypto
import TandemProtocol
import TandemStore

/// A Mac-initiated rotation still waiting on phones: when it started and the display names of the
/// phones that have not acked the new key.
public struct MacPendingRotation: Equatable, Sendable {
    public let startedAt: Date
    public let phoneNames: [String]
}

public enum MacRotationOutcome: Equatable, Sendable {
    case switched
    case awaitingPhones
    case unavailable
}

/// The production composition of Mac-initiated key rotation (E70-16): one ``RotationCoordinator``
/// (its lock covers every caller) and one ``RotationInitiator`` per authenticated control session,
/// shared by the Key settings tab (``rotate()``) and the ``RotationScheduler``. As a
/// ``SessionService`` it feeds each session's `RotationChallenge`, `RotationAck` and `RotationReject`
/// frames to that session's initiator; sessions are authenticated by their pinned handshake, and the
/// initiator itself sends nothing unless the peer holds its primary pin. Never logs keys.
public final class MacKeyRotation: SessionService, Sendable {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "MacKeyRotation")

    private struct Entry {
        let initiator: RotationInitiator
        let reader: Task<Void, Never>
    }

    private struct Observation {
        var observer: (@Sendable (Bool) -> Void)?
        var scheduler: Task<Void, Never>?
    }

    private let keychainStore: any KeychainStore
    private let trustStore: TrustStore
    private let window: any PairingWindowState
    private let dateProvider: DateProvider
    private let clock: any Clock<Duration>
    private let interval: Duration
    private let dueStore: any NextRotationDueStore
    private let coordinator: RotationCoordinator
    private let switched: SwitchSignal
    private let entries = Mutex<[SpkiFingerprint: Entry]>([:])
    private let observation = Mutex(Observation())
    private let authenticated: AsyncStream<Bool>
    private let authenticatedChanges: AsyncStream<Bool>.Continuation

    public convenience init(
        keychainStore: any KeychainStore,
        trustStore: TrustStore,
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider,
        interval: Duration,
        dueDateURL: URL,
        onSwitched: @escaping @Sendable () -> Void
    ) {
        self.init(
            keychainStore: keychainStore,
            trustStore: trustStore,
            window: window,
            dateProvider: dateProvider,
            clock: ContinuousClock(),
            interval: interval,
            dueStore: FileNextRotationDueStore(url: dueDateURL),
            onSwitched: onSwitched
        )
    }

    init(
        keychainStore: any KeychainStore,
        trustStore: TrustStore,
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider,
        clock: any Clock<Duration>,
        interval: Duration,
        dueStore: any NextRotationDueStore,
        onSwitched: @escaping @Sendable () -> Void
    ) {
        self.keychainStore = keychainStore
        self.trustStore = trustStore
        self.window = window
        self.dateProvider = dateProvider
        self.clock = clock
        self.interval = interval
        self.dueStore = dueStore
        let signal = SwitchSignal()
        switched = signal
        coordinator = RotationCoordinator(
            keychainStore: keychainStore,
            trustStore: trustStore,
            window: window,
            dateProvider: dateProvider,
            onSwitched: {
                signal.fire()
                onSwitched()
            }
        )
        (authenticated, authenticatedChanges) = AsyncStream<Bool>.makeStream()
    }

    /// Re-runs whatever a restart interrupted; call once at launch.
    public func resume() {
        do {
            try coordinator.resume()
        } catch {
            Self.logger.error("rotation resume failed")
        }
    }

    /// Starts the scheduler over the authenticated-session signal; call once.
    public func startScheduler() {
        let scheduler = RotationScheduler(
            clock: clock,
            dateProvider: dateProvider,
            interval: interval,
            store: dueStore,
            rotate: { [weak self] in await self?.rotate() == .switched ? .committed : .notCommitted }
        )
        let stream = authenticated
        let task = Task { await scheduler.run(authenticated: stream) }
        observation.withLock { $0.scheduler = task }
    }

    /// Reports whether any authenticated control session is connected, now and on every change.
    public func observeAuthenticated(_ observer: @escaping @Sendable (Bool) -> Void) {
        observation.withLock { $0.observer = observer }
        observer(hasAuthenticatedSession)
    }

    public var hasAuthenticatedSession: Bool {
        entries.withLock { !$0.isEmpty }
    }

    public func activeSpkiDer() throws -> Data {
        try RotationKeyProvider(keychainStore: keychainStore).activeSpkiDer()
    }

    /// Begins a rotation (or joins the one in progress), offers it to every connected phone and waits
    /// for the identity to switch.
    public func rotate() async -> MacRotationOutcome {
        let switchEvents = switched.subscribe()
        do {
            try coordinator.begin()
        } catch {
            return .unavailable
        }
        let initiators = entries.withLock { $0.values.map(\.initiator) }
        guard !initiators.isEmpty else { return .awaitingPhones }
        for initiator in initiators { await initiator.sendIfPending() }
        return await awaitSwitch(switchEvents) ? .switched : .awaitingPhones
    }

    public func pendingRotation() -> MacPendingRotation? {
        guard let attempt = try? coordinator.attempt(), !attempt.committed,
              let phones = try? trustStore.list() else { return nil }
        let pending = Set(attempt.pendingRecordIds)
        return MacPendingRotation(
            startedAt: attempt.startedAt,
            phoneNames: phones.filter { pending.contains($0.recordId.hexString) }.map(\.displayName)
        )
    }

    public func finish() throws {
        try coordinator.finish()
    }

    public func cancel() throws {
        try coordinator.cancel()
    }

    public func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let initiator = RotationInitiator(
            session: session,
            handshakeFingerprint: peer,
            coordinator: coordinator,
            trustStore: trustStore,
            window: window,
            dateProvider: dateProvider,
            clock: clock
        )
        let frames = await session.receive(.control)
        let reader = Task {
            for await frame in frames {
                switch frame.payload {
                case .rotationChallenge(let message)?: await initiator.receivedChallenge(message.challenge)
                case .rotationAck?: await initiator.receivedAck()
                case .rotationReject(let message)?: await initiator.receivedReject(message.reason)
                default: continue
                }
            }
        }
        let previous = entries.withLock { $0.updateValue(Entry(initiator: initiator, reader: reader), forKey: peer) }
        previous?.reader.cancel()
        publishAuthenticated()
    }

    public func detach(peer: SpkiFingerprint) async {
        entries.withLock { $0.removeValue(forKey: peer) }?.reader.cancel()
        publishAuthenticated()
    }

    private func publishAuthenticated() {
        let connected = hasAuthenticatedSession
        authenticatedChanges.yield(connected)
        observation.withLock { $0.observer }?(connected)
    }

    private func awaitSwitch(_ events: AsyncStream<Void>) async -> Bool {
        let clock = clock
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events { return true }
                return false
            }
            group.addTask {
                try? await clock.sleep(for: RotationInitiator.ackDeadline)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

private final class SwitchSignal: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    func subscribe() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    func fire() {
        let active = continuations.withLock { $0.values.map { $0 } }
        for continuation in active { continuation.yield() }
    }
}
