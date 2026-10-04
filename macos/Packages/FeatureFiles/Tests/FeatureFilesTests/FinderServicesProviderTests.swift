import AppKit
import Foundation
import Testing
@testable import FeatureFiles

private final class RecordingTransferService: FileTransferService, @unchecked Sendable {
    let isConnected: Bool
    private(set) var started: [URL] = []

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    func startOffer(for url: URL) async {
        started.append(url)
    }
}

private struct UnusedFilePicker: FilePicker {
    @MainActor
    func pickFiles() async -> [URL] {
        []
    }
}

private func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
}

@MainActor
struct FinderServicesProviderTests {
    private func makeProvider(_ transfer: RecordingTransferService) -> FinderServicesProvider {
        FinderServicesProvider(handler: SendEntryHandler(picker: UnusedFilePicker(), transfer: transfer))
    }

    @Test func servicesProvider_twoFileUrls_startsTwoOffers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("a.txt"), directory.appendingPathComponent("b.txt")]
        for url in urls { try Data("x".utf8).write(to: url) }
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        let transfer = RecordingTransferService()

        let error = await makeProvider(transfer).send(pasteboard: pasteboard)

        #expect(error == nil)
        #expect(transfer.started == urls)
    }

    @Test func servicesProvider_noFileUrl_noOfferAndErrorReturned() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        let transfer = RecordingTransferService()

        let error = await makeProvider(transfer).send(pasteboard: pasteboard)

        #expect(error == FinderServicesProvider.noFilesError)
        #expect(transfer.started.isEmpty)
    }

    @Test func servicesProvider_notConnected_noOfferAndErrorReturned() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.txt")] as [NSURL])
        let transfer = RecordingTransferService(isConnected: false)

        let error = await makeProvider(transfer).send(pasteboard: pasteboard)

        #expect(error == FinderServicesProvider.notConnectedError)
        #expect(transfer.started.isEmpty)
    }
}
