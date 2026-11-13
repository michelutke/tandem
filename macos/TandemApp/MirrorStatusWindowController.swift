import AppKit
import FeatureMirror
import Observation
import SwiftUI
import TandemDesign

/// Shows the dark "Waiting." / "Declined." window (ui-spec §7.1) while ``MirrorRequestViewModel`` is
/// waiting for or was declined by the phone, and closes it when the request returns to idle (accepted,
/// cancelled or timed out). Cancel and Close, like the window's close button, only dismiss: they
/// send nothing.
@MainActor
final class MirrorStatusWindowController: NSObject, NSWindowDelegate {
    private let viewModel: MirrorRequestViewModel
    private var window: NSWindow?

    init(viewModel: MirrorRequestViewModel) {
        self.viewModel = viewModel
        super.init()
        stateChanged()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = viewModel.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.stateChanged()
                self?.observe()
            }
        }
    }

    private func stateChanged() {
        switch viewModel.state {
        case .waiting, .declined: show()
        case .idle, .notConnected: close()
        }
    }

    private func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: MirrorStatusHost(viewModel: viewModel))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        guard let window else { return }
        window.delegate = nil
        self.window = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        viewModel.cancel()
    }
}

private struct MirrorStatusHost: View {
    let viewModel: MirrorRequestViewModel

    var body: some View {
        content
            .padding(.top, TandemSpacing.large)
            .glassSurface(cornerRadius: 0)
            .ignoresSafeArea()
            .tandemWindowChrome()
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .declined:
            MirrorStatusView(
                title: "Declined.",
                detail: "Nothing was shared.",
                actionTitle: "Close",
                onAction: { viewModel.cancel() }
            )
        case .waiting, .idle, .notConnected:
            MirrorStatusView(
                title: "Waiting.",
                detail: viewModel.waitingDetail,
                actionTitle: "Cancel",
                onAction: { viewModel.cancel() }
            )
        }
    }
}
