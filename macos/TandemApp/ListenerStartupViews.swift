import AppKit
import Observation
import SwiftUI
import TandemDesign
import TandemTransport

/// Shows `ready` while the listener is running (or was never started, as in harness and scenario
/// hosts) and `failed` while the start is failing. A successful retry rebuilds `ready`, so views
/// composed from the lifecycle pick it up without a relaunch. The app becoming active while failed
/// triggers one retry; the failed state stays visible until a start succeeds.
struct ListenerStartupGate<Lifecycle, Ready: View, Failed: View>: View {
    let model: ListenerStartupModel<Lifecycle>
    let retry: @MainActor () -> Void
    @ViewBuilder let ready: () -> Ready
    @ViewBuilder let failed: (_ reason: ListenerFailureReason, _ retry: @escaping @MainActor () -> Void) -> Failed

    var body: some View {
        Group {
            if case .failed(let reason) = model.phase {
                failed(reason, retry)
            } else {
                ready().id(model.generation)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            retry()
        }
    }
}

/// "Tandem can't start." with the reason and a Retry button (ui-spec §9, invariant 5).
struct ListenerFailureView: View {
    let reason: ListenerFailureReason
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            Text("Tandem can't start.")
                .tandemTextStyle(TandemTypography.titlePairBold())
                .foregroundStyle(TandemColor.alert)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("Tandem can't start. \(reason.message)")
            Text(reason.message)
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
                .accessibilityIdentifier("listenerFailureReason")
            PillButton("Retry", action: onRetry)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("listenerRetryButton")
        }
    }

    private var identifier: String {
        switch reason {
        case .keychainAccess, .identityUnavailable: "identityUnavailableLabel"
        case .portUnavailable, .unknown: "listenerUnavailableLabel"
        }
    }
}

/// The failure state as the main window's whole content.
struct ListenerFailureWindowContent: View {
    let reason: ListenerFailureReason
    let onRetry: () -> Void

    var body: some View {
        ListenerFailureView(reason: reason, onRetry: onRetry)
            .padding(TandemSpacing.windowPadding)
            .frame(minWidth: 420, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity, alignment: .topLeading)
            .glassSurface(cornerRadius: 0)
            .ignoresSafeArea()
            .tandemWindowChrome()
    }
}

/// Remembers, across launches, that this Mac's identity was regenerated (so every paired phone
/// fails its pin check) until a pairing succeeds again (invariant 5, SPEC.md).
@MainActor
@Observable
final class IdentityResetNotice {
    static let shared = IdentityResetNotice()
    nonisolated private static let defaultsKey = "identityResetRequiresRePair"

    private(set) var isVisible = UserDefaults.standard.bool(forKey: defaultsKey)

    /// Called from the identity bootstrap, possibly off the main thread.
    nonisolated static func markReset() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        Task { @MainActor in shared.isVisible = true }
    }

    func clear() {
        UserDefaults.standard.set(false, forKey: Self.defaultsKey)
        isVisible = false
    }
}

/// "This Mac's key changed. Pair your phone again." with a Pair phone button (ui-spec state.keyReset).
struct RePairNoticeView: View {
    let onPairPhone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            Text("This Mac's key changed. Pair your phone again.")
                .tandemTextStyle(TandemTypography.rowTitle(size: 14))
                .foregroundStyle(TandemColor.alert)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rePairNoticeLabel")
            PillButton("Pair phone", action: onPairPhone)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("rePairNoticeButton")
        }
    }
}
