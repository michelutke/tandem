import Cocoa

final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func send(_ sender: AnyObject?) {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: cancelError)
    }
}
