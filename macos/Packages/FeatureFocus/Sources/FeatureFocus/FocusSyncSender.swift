import TandemProtocol

/// Mac side of Focus/DND sync (E72-09, PRD F-10.2). Sends one `FocusState` on CONTROL per Focus
/// change and nothing for an unchanged state. After the phone answers
/// `FocusSyncCapability { available: false }` it sends nothing until `available: true`.
public actor FocusSyncSender {
    private let source: any FocusStateSource
    private let session: any TandemSession
    private var lastSent: Bool?
    private var phoneAvailable = true
    private var changesTask: Task<Void, Never>?
    private var capabilityTask: Task<Void, Never>?

    public init(source: any FocusStateSource, session: any TandemSession) {
        self.source = source
        self.session = session
    }

    public func start() {
        changesTask?.cancel()
        capabilityTask?.cancel()
        let source = source
        let session = session
        changesTask = Task { [weak self] in
            for await isOn in source.changes {
                await self?.handle(focusOn: isOn)
            }
        }
        capabilityTask = Task { [weak self] in
            for await frame in await session.receive(.control) {
                guard case .focusSyncCapability(let capability)? = frame.payload else { continue }
                await self?.handle(capability: capability)
            }
        }
    }

    public func stop() {
        changesTask?.cancel()
        capabilityTask?.cancel()
        changesTask = nil
        capabilityTask = nil
    }

    public func handle(focusOn: Bool) async {
        guard phoneAvailable, focusOn != lastSent else { return }
        var state = Tandem_V1_FocusState()
        state.on = focusOn
        do {
            try await session.send(.control, payload: .focusState(state))
            lastSent = focusOn
        } catch {
            return
        }
    }

    public func handle(capability: Tandem_V1_FocusSyncCapability) {
        phoneAvailable = capability.available
    }
}
