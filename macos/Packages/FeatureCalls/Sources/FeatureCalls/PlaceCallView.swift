import SwiftUI
import TandemDesign

/// Place-call entry (E52-07, ui-spec Main window · Calls): a Call button, the SIM choice when the
/// phone has 2+ SIMs, then the dialing, tap-on-phone and failed states. Numbers are never shown in
/// logs (invariant 7).
public struct PlaceCallView: View {
    private let viewModel: PlaceCallViewModel
    private let number: String

    public init(viewModel: PlaceCallViewModel, number: String) {
        self.viewModel = viewModel
        self.number = number
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            switch viewModel.state {
            case .idle:
                callButton
            case .choosingSim(let sims):
                ForEach(sims) { sim in
                    PillButton(sim.name) { Task { await viewModel.choose(subscriptionId: sim.id) } }
                        .accessibilityIdentifier("callSim-\(sim.id)")
                }
            case .dialing:
                status("Calling.", color: TandemColor.ink2)
            case .needsPhoneTap:
                status("Tap the notification on your phone.", color: TandemColor.ink)
                callButton
            case .failed:
                status("Couldn't call.", color: TandemColor.alert)
                callButton
            }
        }
        .task { viewModel.start() }
    }

    private var callButton: some View {
        Button { Task { await viewModel.place(number: number) } } label: {
            HStack(spacing: TandemSpacing.extraSmall) {
                Image(systemName: "phone")
                Text("Call")
            }
            .tandemTextStyle(TandemTypography.rowTitle(size: 12))
            .foregroundStyle(TandemColor.ink)
            .padding(.horizontal, TandemSpacing.medium)
            .padding(.vertical, TandemSpacing.small)
            .background(Capsule().fill(TandemColor.ink.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("callButton")
    }

    private func status(_ text: String, color: Color) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(color)
            .accessibilityIdentifier("callStatus")
    }
}
