import AppKit
import SwiftUI
import TandemDesign

/// The Photos section's grid (backlog E41-05, ui-spec §7.1): a title pair, the limited-access
/// banner when the phone shares only some photos, and a lazy grid whose visible index range
/// drives paging and thumbnail requests in ``PhotoGridViewModel``.
public struct PhotoGridView: View {
    private let viewModel: PhotoGridViewModel
    private let deviceName: String
    @State private var visibleIndices: Set<Int> = []

    private static let cellSize: CGFloat = 96

    public init(viewModel: PhotoGridViewModel, deviceName: String = "Your phone") {
        self.viewModel = viewModel
        self.deviceName = deviceName
    }

    public var body: some View {
        Group {
            if viewModel.showsNoAccess {
                SectionEmptyState(
                    kind: .noAccess(section: "Photos", deviceName: deviceName),
                    identifier: "photoNoAccessEmptyState"
                )
            } else {
                grid
            }
        }
        .task { await viewModel.loadFirstPage() }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            header
            if viewModel.showsLimitedAccessBanner {
                limitedAccessBanner
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cellSize), spacing: TandemSpacing.small)],
                    spacing: TandemSpacing.small
                ) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        cell(for: item.id, index: index)
                            .contextMenu {
                                Button("Download") { Task { await viewModel.download(id: item.id) } }
                            }
                            .onAppear { cellAppeared(index) }
                            .onDisappear { visibleIndices.remove(index) }
                    }
                }
            }
            .accessibilityIdentifier("photoGrid")
            footer
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            TitleBlock(subject: "Photos.", state: "\(viewModel.items.count.formatted()) on phone.")
            Spacer()
            if !viewModel.selectedIds.isEmpty {
                PillButton("Download \(viewModel.selectedIds.count)", kind: .secondary) {
                    Task { await viewModel.downloadSelected() }
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("photoDownloadSelectedButton")
            }
        }
    }

    private var footer: some View {
        let loaded = viewModel.items.count.formatted()
        let progress = viewModel.totalCount.map { "Loaded \(loaded) of \($0.formatted())" } ?? "Loaded \(loaded)"
        return Text("\(progress) · thumbnails cached locally")
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(TandemColor.ink2)
            .accessibilityIdentifier("photoGridFooter")
    }

    private var limitedAccessBanner: some View {
        HStack(spacing: TandemSpacing.medium) {
            Text("Limited access. Only selected photos are shown.")
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink)
            PillButton("Select more on phone", kind: .secondary) {
                Task { await viewModel.selectMoreOnPhone() }
            }
        }
        .accessibilityIdentifier("limitedAccessBanner")
    }

    @ViewBuilder
    private func cell(for id: String, index: Int) -> some View {
        let isSelected = viewModel.isSelected(id: id)
        return Group {
            if let data = viewModel.thumbnails[id], let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                TandemColor.ink.opacity(0.05)
            }
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .clipShape(RoundedRectangle(cornerRadius: TandemRadius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TandemRadius.row, style: .continuous)
                .stroke(TandemColor.ink, lineWidth: isSelected ? 2 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleSelection(id: id) }
        .accessibilityElement()
        .accessibilityLabel("Photo \(index + 1)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func cellAppeared(_ index: Int) {
        visibleIndices.insert(index)
        guard let first = visibleIndices.min(), let last = visibleIndices.max() else { return }
        Task { await viewModel.visibleRangeChanged(first...last) }
    }
}
