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

private struct FakeFilePicker: FilePicker {
    let picked: [URL]

    @MainActor
    func pickFiles() async -> [URL] {
        picked
    }
}

private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeFile(in directory: URL, name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
}

@MainActor
struct SendEntryHandlerTests {
    @Test func dropHandler_twoFileUrls_startsTwoOffers() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [try makeFile(in: directory, name: "a.txt"), try makeFile(in: directory, name: "b.txt")]
        let transfer = RecordingTransferService()
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: transfer)

        let result = await handler.handleDrop(urls: urls)

        #expect(result == .started(count: 2))
        #expect(transfer.started == urls)
    }

    @Test func dropHandler_folderUrl_noOfferAndUnsupportedFolder() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transfer = RecordingTransferService()
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: transfer)

        let result = await handler.handleDrop(urls: [directory])

        #expect(result == .unsupportedFolder)
        #expect(transfer.started.isEmpty)
    }

    @Test func dropHandler_disconnected_noOfferAndNotConnected() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeFile(in: directory, name: "a.txt")
        let transfer = RecordingTransferService(isConnected: false)
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: transfer)

        let result = await handler.handleDrop(urls: [file])

        #expect(result == .notConnected)
        #expect(transfer.started.isEmpty)
    }

    @Test func dropHandler_noTransferService_notConnected() async throws {
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: nil)

        let result = await handler.handleDrop(urls: [URL(fileURLWithPath: "/tmp/a.txt")])

        #expect(result == .notConnected)
    }

    @Test func sendFileQuickAction_pickerCancelled_noOfferStarted() async {
        let transfer = RecordingTransferService()
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: transfer)

        let result = await handler.sendFileQuickAction()

        #expect(result == .cancelled)
        #expect(transfer.started.isEmpty)
    }

    @Test func sendFileQuickAction_fileChosen_startsOneOffer() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeFile(in: directory, name: "a.txt")
        let transfer = RecordingTransferService()
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: [file]), transfer: transfer)

        let result = await handler.sendFileQuickAction()

        #expect(result == .started(count: 1))
        #expect(transfer.started == [file])
    }

    @Test func dropHandler_twoFileUrls_lastResultReportsStarted() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [try makeFile(in: directory, name: "a.txt")]
        let handler = SendEntryHandler(picker: FakeFilePicker(picked: []), transfer: RecordingTransferService())

        _ = await handler.handleDrop(urls: urls)

        #expect(handler.lastResult == .started(count: 1))
    }

    @Test func sendFileQuickAction_notConnected_lastResultReportsNotConnected() async {
        let handler = SendEntryHandler(
            picker: FakeFilePicker(picked: []),
            transfer: RecordingTransferService(isConnected: false)
        )

        _ = await handler.sendFileQuickAction()

        #expect(handler.lastResult == .notConnected)
    }
}
