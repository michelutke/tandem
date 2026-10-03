import Cocoa
import FeatureFiles
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await enqueueSharedFiles() }
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: cancelError)
    }

    private func enqueueSharedFiles() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        var files: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                files.append(url)
            }
        }
        do {
            try SendRequestQueue().enqueue(files: files)
            SendRequestWake.post()
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }
}
