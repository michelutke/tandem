import Foundation
import Network
import Security

final class SpikeListener {
    private let listener: NWListener
    private let handshakeDeadline: TimeInterval
    private let exitAfter: Int?
    private var terminalCount = 0
    private let lock = NSLock()
    private var openConnections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16, options: NWProtocolTLS.Options, handshakeDeadline: TimeInterval, exitAfter: Int?) throws {
        let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        self.handshakeDeadline = handshakeDeadline
        self.exitAfter = exitAfter
        self.listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { state in
            print("EVENT type=listener-state state=\(state)")
            if case .failed(let error) = state {
                print("EVENT type=listener-failed error=\"\(error)\"")
                exit(1)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        let start = DispatchTime.now()
        let id = ObjectIdentifier(connection)
        lock.lock(); openConnections[id] = connection; lock.unlock()

        // Acceptance item (d): can the listener read the remote endpoint before the TLS
        // handshake completes? `connection.endpoint` is available immediately, before `start()`.
        print("EVENT type=pre-handshake-endpoint remote=\(connection.endpoint)")

        var reachedReady = false
        let deadlineWorkItem = DispatchWorkItem { [weak self] in
            guard !reachedReady else { return }
            print("EVENT type=handshake-deadline-cancel remote=\(connection.endpoint) deadline_s=\(self?.handshakeDeadline ?? -1)")
            connection.cancel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeDeadline, execute: deadlineWorkItem)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            switch state {
            case .ready:
                reachedReady = true
                deadlineWorkItem.cancel()
                self.describeReady(connection: connection, elapsedMs: elapsedMs)
                self.receiveLoop(connection)
            case .failed(let error):
                deadlineWorkItem.cancel()
                print("EVENT type=failed role=server remote=\(connection.endpoint) error=\"\(error)\" elapsed_ms=\(elapsedMs)")
                self.finish(connection)
            case .cancelled:
                print("EVENT type=cancelled role=server remote=\(connection.endpoint) elapsed_ms=\(elapsedMs)")
                self.finish(connection)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func describeReady(connection: NWConnection, elapsedMs: Double) {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            print("EVENT type=ready role=server remote=\(connection.endpoint) note=\"no TLS metadata\" elapsed_ms=\(elapsedMs)")
            return
        }
        let secMetadata = metadata.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secMetadata)
        var alpn = "none"
        if let negotiated = sec_protocol_metadata_get_negotiated_protocol(secMetadata) {
            alpn = String(cString: negotiated)
        }
        var exporterSha = "unavailable"
        if let exporter = channelBindingExporter(from: secMetadata) {
            exporterSha = sha256Hex(exporter)
        }
        print("EVENT type=ready role=server remote=\(connection.endpoint) tls_version=\(version) alpn=\(alpn) exporter_sha256=\(exporterSha) elapsed_ms=\(elapsedMs)")
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                let text = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
                print("EVENT type=app-data role=server remote=\(connection.endpoint) bytes=\(data.count) text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                connection.send(content: "ack\n".data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if isComplete || error != nil {
                self?.finish(connection)
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        openConnections.removeValue(forKey: id)
        terminalCount += 1
        let count = terminalCount
        lock.unlock()
        if let exitAfter, count >= exitAfter {
            print("EVENT type=exit-after-reached count=\(count)")
            listener.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }
}
