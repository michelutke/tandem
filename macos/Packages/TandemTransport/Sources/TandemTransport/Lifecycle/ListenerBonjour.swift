import Foundation

/// Keeps this Mac's `_tandem._tcp` advertisement (SPEC.md "Discovery TXT record") pointing at the
/// running listener: every listener start, including each rebind after sleep or a network change,
/// replaces the previous ``BonjourAdvertiser`` with one for the new port and the identity's current
/// SPKI fingerprint (which a key rotation changes), publishing today's id immediately. Nothing is
/// advertised while no identity is available.
public actor ListenerBonjour {
    private let publisher: any BonjourPublisher
    private let macSpkiFingerprint: @Sendable () -> Data?
    private let dateProvider: DateProvider
    private let clock: any Clock<Duration>
    private var advertiser: BonjourAdvertiser?
    private var generation = 0

    public init(
        publisher: any BonjourPublisher,
        macSpkiFingerprint: @escaping @Sendable () -> Data?,
        dateProvider: @escaping DateProvider,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.publisher = publisher
        self.macSpkiFingerprint = macSpkiFingerprint
        self.dateProvider = dateProvider
        self.clock = clock
    }

    public func listenerStarted(port: UInt16) async {
        generation += 1
        let mine = generation
        await retireAdvertiser()
        guard mine == generation, let fingerprint = macSpkiFingerprint() else { return }
        let next = BonjourAdvertiser(
            publisher: publisher,
            macSpkiFingerprint: fingerprint,
            port: port,
            dateProvider: dateProvider,
            clock: clock
        )
        advertiser = next
        await next.start()
    }

    /// Withdraws the advertisement: the listener it pointed at is gone. A start still suspended
    /// when this runs publishes nothing.
    public func listenerStopped() async {
        generation += 1
        await retireAdvertiser()
    }

    private func retireAdvertiser() async {
        let old = advertiser
        advertiser = nil
        await old?.stop()
    }
}
