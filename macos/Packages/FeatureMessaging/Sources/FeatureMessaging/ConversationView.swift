import SwiftUI
import TandemDesign

/// One conversation (backlog E50-08, ui-spec §7.1): bubbles by direction, a meta line under each
/// outbound bubble ("Not sent · no service · Retry" in `alert` when failed), then the composer
/// with a SIM picker when the phone has 2+ SIMs.
public struct ConversationView: View {
    @Bindable private var viewModel: ConversationViewModel
    private let headerAccessory: (@MainActor (String) -> AnyView)?
    private let offlineComposerText: String?

    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - headerAccessory: hosted beside the title with the thread's phone number once loaded
    ///     (the app target's Call button, E52-10).
    ///   - offlineComposerText: when non-nil the phone is offline: the composer is disabled and
    ///     shows this text ("Sends when Pixel 9 is back", ui-spec §7.1).
    public init(
        viewModel: ConversationViewModel,
        headerAccessory: (@MainActor (String) -> AnyView)? = nil,
        offlineComposerText: String? = nil
    ) {
        self.viewModel = viewModel
        self.headerAccessory = headerAccessory
        self.offlineComposerText = offlineComposerText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TandemSpacing.small) {
                    ForEach(viewModel.bubbles) { bubble in
                        bubbleRow(bubble)
                    }
                }
            }
            .accessibilityIdentifier("messageList")
            composer
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await viewModel.reload() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.title).")
                    .tandemTextStyle(TandemTypography.sectionTitleBold())
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
            }
            Spacer()
            if let headerAccessory, !viewModel.callAddress.isEmpty {
                headerAccessory(viewModel.callAddress)
            }
        }
        .padding(.bottom, TandemSpacing.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
        }
    }

    private var subtitle: String? {
        let address = viewModel.callAddress
        return address.isEmpty || address == viewModel.title ? nil : address
    }

    private func bubbleRow(_ bubble: MessageBubble) -> some View {
        VStack(alignment: bubble.isOutbound ? .trailing : .leading, spacing: TandemSpacing.extraSmall) {
            Text(bubble.body)
                .tandemTextStyle(TandemTypography.body())
                .frame(maxWidth: 380, alignment: bubble.isOutbound ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(bubble.isOutbound ? TandemColor.paper : TandemColor.ink)
                .padding(.horizontal, TandemSpacing.medium)
                .padding(.vertical, TandemSpacing.small)
                .background(
                    RoundedRectangle(cornerRadius: TandemSpacing.large)
                        .fill(bubble.isOutbound ? TandemColor.ink : TandemColor.ink.opacity(0.05))
                )
            meta(bubble)
        }
        .frame(maxWidth: .infinity, alignment: bubble.isOutbound ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messageBubble-\(bubble.id)")
    }

    @ViewBuilder
    private func meta(_ bubble: MessageBubble) -> some View {
        switch bubble.state {
        case .received:
            EmptyView()
        case .sending:
            metaText("Sending.", color: TandemColor.ink2)
        case .sent:
            metaText("Sent", color: TandemColor.ink2)
        case .delivered:
            metaText("Delivered", color: TandemColor.ink2)
        case .failed(let failure):
            HStack(spacing: TandemSpacing.extraSmall) {
                metaText("Not sent · \(failure.reason) ·", color: TandemColor.alert)
                Button("Retry") { Task { await viewModel.retryTapped(bubble) } }
                    .buttonStyle(.plain)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.alert)
                    .accessibilityIdentifier("retryButton-\(bubble.id)")
            }
        }
    }

    private func metaText(_ text: String, color: Color) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(color)
    }

    private var isOffline: Bool { offlineComposerText != nil }

    private var composer: some View {
        HStack(spacing: TandemSpacing.small) {
            TextField(offlineComposerText ?? "Text message", text: $viewModel.draft)
                .textFieldStyle(.plain)
                .tandemTextStyle(TandemTypography.body())
                .disabled(isOffline)
                .onSubmit { Task { await viewModel.sendTapped() } }
                .accessibilityIdentifier("composeField")
            if viewModel.showsSimPicker {
                Picker("SIM", selection: $viewModel.selectedSubscriptionId) {
                    ForEach(viewModel.sims) { sim in
                        Text(sim.name).tag(Int32?.some(sim.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("simPicker")
            }
            Button { Task { await viewModel.sendTapped() } } label: {
                Image(systemName: "arrow.up")
                    .foregroundStyle(TandemColor.paper)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(TandemColor.ink))
                    .opacity(isOffline ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .disabled(!sendEnabled)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("sendButton")
        }
        .padding(.leading, TandemSpacing.large)
        .padding(.trailing, TandemSpacing.small)
        .padding(.vertical, TandemSpacing.small)
        .overlay(Capsule().stroke(TandemColor.line, lineWidth: 1))
    }

    private var sendEnabled: Bool { viewModel.canSend && !isOffline }
}
