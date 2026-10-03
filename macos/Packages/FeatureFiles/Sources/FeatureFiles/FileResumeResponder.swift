import Foundation
import TandemProtocol

/// Sender-side router for `FileResumeRequest`s on one authenticated session: known ids resume their
/// ``FileSender``, anything else is answered `FileReject{UNKNOWN_TRANSFER}`.
public actor FileResumeResponder {
    private let session: any TandemSession
    private var senders: [String: FileSender] = [:]

    public init(session: any TandemSession) {
        self.session = session
    }

    public func register(id: String, sender: FileSender) {
        senders[id] = sender
    }

    public func handle(resume: Tandem_V1_FileResumeRequest) async {
        guard let sender = senders[resume.id], await !sender.isCancelled else {
            var reject = Tandem_V1_FileReject()
            reject.id = resume.id
            reject.reason = .unknownTransfer
            try? await session.send(.files, payload: .fileReject(reject))
            return
        }
        await sender.handle(resume: resume)
    }
}
