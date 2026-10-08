import SwiftUI
import TandemDesign

/// The main window's Calls section (ui-spec §7.1): the in-call bar on the left, contact search and
/// call buttons on the right. Audio stays on the phone.
public struct CallsSectionView: View {
    @Bindable private var viewModel: CallsSectionViewModel
    private let placeCall: PlaceCallViewModel
    private let callAlert: CallAlertViewModel?

    @Environment(\.colorSchemeContrast) private var contrast

    public init(viewModel: CallsSectionViewModel, placeCall: PlaceCallViewModel, callAlert: CallAlertViewModel?) {
        self.viewModel = viewModel
        self.placeCall = placeCall
        self.callAlert = callAlert
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            TitleBlock(subject: "Calls.", state: "Audio stays on the phone.", size: 26)
            HStack(alignment: .top, spacing: TandemSpacing.extraLarge * 2) {
                inCall
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                callSomeone
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            placeCall.start()
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private var inCall: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            caption("In call")
            if let callAlert, let call = callAlert.activeCall {
                Text(call.displayTitle)
                    .tandemTextStyle(TandemTypography.titlePairBold(size: 36))
                    .foregroundStyle(TandemColor.ink)
                    .accessibilityIdentifier("inCallName")
                if !call.isDialing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(call.elapsedText(at: context.date))
                            .tandemTextStyle(TandemTypography.displayNumeral(size: 56))
                            .foregroundStyle(TandemColor.ink)
                            .accessibilityIdentifier("inCallTimer")
                    }
                }
                PillButton("Hang up", kind: .destructive) { Task { await callAlert.hangUp() } }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("hangUpButton")
            } else {
                Text("No active call.")
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier("noActiveCall")
            }
        }
    }

    private var callSomeone: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            caption("Call someone")
            TextField("Search contacts", text: $viewModel.query)
                .textFieldStyle(.plain)
                .tandemTextStyle(TandemTypography.titlePairRegular(size: 22))
                .accessibilityIdentifier("callSearchField")
            placeCallStatus
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.visibleContacts) { row in
                        contactRow(row)
                    }
                }
            }
            .overlay(alignment: .top) { hairline }
            .accessibilityIdentifier("callContactList")
        }
    }

    @ViewBuilder
    private var placeCallStatus: some View {
        switch placeCall.state {
        case .idle:
            EmptyView()
        case .choosingSim(let sims):
            HStack {
                ForEach(sims) { sim in
                    PillButton(sim.name, kind: .secondary) { Task { await placeCall.choose(subscriptionId: sim.id) } }
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("callSim-\(sim.id)")
                }
            }
        case .dialing:
            status(placeCall.statusMessage ?? "", color: TandemColor.ink2)
        case .needsPhoneTap:
            status(placeCall.statusMessage ?? "", color: TandemColor.ink)
        case .failed:
            status(placeCall.statusMessage ?? "", color: TandemColor.alert)
        }
    }

    private func contactRow(_ row: CallContactRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
                Text(row.displayNumber)
                    .tandemTextStyle(TandemTypography.metaMono())
                    .foregroundStyle(TandemColor.ink2)
            }
            Spacer()
            Button { Task { await placeCall.place(number: row.number) } } label: {
                Image(systemName: "phone")
                    .foregroundStyle(TandemColor.paper)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(TandemColor.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call \(row.name)")
            .accessibilityIdentifier("callButton-\(row.id)")
        }
        .padding(.vertical, TandemSpacing.small + TandemSpacing.extraSmall)
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(TandemColor.ink2)
    }

    private func status(_ text: String, color: Color) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(color)
            .accessibilityIdentifier("callStatus")
    }
}
