import Foundation
import Network
import Security

final class SpikeClient {
    private let connection: NWConnection
    private let start = DispatchTime.now()
    private var finished = false

    init(host: String, port: UInt16, options: NWProtocolTLS.Options) {
        let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
    }

    func run(timeout: TimeInterval) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 3

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - self.start.uptimeNanoseconds) / 1_000_000.0
            switch state {
            case .ready:
                self.describeReady(elapsedMs: elapsedMs)
                self.sendHello { code in
                    exitCode = code
                    self.finish(semaphore)
                }
            case .failed(let error):
                print("EVENT type=failed role=client error=\"\(error)\" elapsed_ms=\(elapsedMs)")
                exitCode = 1
                self.finish(semaphore)
            case .waiting(let error):
                print("EVENT type=waiting role=client error=\"\(error)\" elapsed_ms=\(elapsedMs)")
            case .cancelled:
                self.finish(semaphore)
            default:
                print("EVENT type=state role=client state=\(state) elapsed_ms=\(elapsedMs)")
            }
        }
        // Gotcha: do NOT use `.main` here. The caller blocks the main thread on a semaphore
        // below (this is a synchronous CLI, not an app with a run loop), so callbacks scheduled
        // on `.main` would never be drained and every connection would silently hang until the
        // outer timeout fires -- indistinguishable from a real hang. A dedicated queue avoids it.
        connection.start(queue: DispatchQueue(label: "spike-client-connection"))

        let deadline = DispatchTime.now() + timeout
        if semaphore.wait(timeout: deadline) == .timedOut {
            print("EVENT type=timeout role=client after_s=\(timeout)")
            connection.cancel()
            return 2
        }
        return exitCode
    }

    private func finish(_ semaphore: DispatchSemaphore) {
        guard !finished else { return }
        finished = true
        semaphore.signal()
    }

    private func describeReady(elapsedMs: Double) {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            print("EVENT type=ready role=client note=\"no TLS metadata\" elapsed_ms=\(elapsedMs)")
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
        print("EVENT type=ready role=client tls_version=\(version) alpn=\(alpn) exporter_sha256=\(exporterSha) elapsed_ms=\(elapsedMs)")
    }

    private func sendHello(completion: @escaping (Int32) -> Void) {
        connection.send(content: "hello\n".data(using: .utf8), completion: .contentProcessed { error in
            if let error {
                print("EVENT type=send-error role=client error=\"\(error)\"")
                completion(1)
                return
            }
            self.connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, error in
                if let data, !data.isEmpty {
                    let text = String(data: data, encoding: .utf8) ?? "<binary>"
                    print("EVENT type=app-data role=client bytes=\(data.count) text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                    completion(0)
                } else {
                    print("EVENT type=recv-error role=client error=\"\(String(describing: error))\"")
                    completion(1)
                }
                self.connection.cancel()
            }
        })
    }
}
