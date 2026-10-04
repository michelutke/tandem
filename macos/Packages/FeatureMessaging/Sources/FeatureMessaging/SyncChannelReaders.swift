import TandemProtocol

/// Reads `session`'s SMS channel until it finishes, feeding every `SmsSyncResponse`,
/// `SendSmsStatus` and `SimList` to `client`. The composition root's one SMS reader (E22-12); let
/// it finish on its own rather than cancelling it.
public func startSmsSyncReader(session: any TandemSession, client: SmsSyncClient) -> Task<Void, Never> {
    Task {
        for await frame in await session.receive(.sms) {
            switch frame.payload {
            case .smsSyncResponse(let response): await client.handle(response)
            case .sendSmsStatus(let status): await client.handle(status)
            case .simList(let simList): await client.handle(simList)
            default: continue
            }
        }
    }
}

/// Reads `session`'s CONTACTS channel until it finishes, feeding every `ContactsSyncResponse` to
/// `client`. A store or send failure for one response is dropped; the next sync request re-pulls
/// from the persisted watermark.
public func startContactsSyncReader(session: any TandemSession, client: ContactsSyncClient) -> Task<Void, Never> {
    Task {
        for await frame in await session.receive(.contacts) {
            guard case .contactsSyncResponse(let response)? = frame.payload else { continue }
            try? await client.handle(response)
        }
    }
}
