import AppKit
import SwiftUI
import TandemDesign

/// The Photos section's grid (backlog E41-05, ui-spec §7.1): a title pair, the limited-access
/// banner when the phone shares only some photos, and a lazy grid whose visible index range
/// drives paging and thumbnail requests in ``PhotoGridViewModel``.
public struct PhotoGridView: View {
    private let viewModel: PhotoGridViewModel
    @State private var visibleIndices: Set<Int> = []

    private static let cellSize: CGFloat = 96

    public init(viewModel: PhotoGridViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            TitleBlock(subject: "Photos.", state: "\(viewModel.items.count) on phone.")
            if viewModel.showsLimitedAccessBanner {
                limitedAccessBanner
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cellSize), spacing: TandemSpacing.small)],
                    spacing: TandemSpacing.small
                ) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        cell(for: item.id)
                            .contextMenu {
                                Button("Download") { Task { await viewModel.download(id: item.id) } }
                            }
                            .onAppear { cellAppeared(index) }
                            .onDisappear { visibleIndices.remove(index) }
                    }
                }
            }
            .accessibilityIdentifier("photoGrid")
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await viewModel.loadFirstPage() }
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
    private func cell(for id: String) -> some View {
        Group {
            if let data = viewModel.thumbnails[id], let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                TandemColor.ink.opacity(0.05)
            }
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .clipped()
    }

    private func cellAppeared(_ index: Int) {
        visibleIndices.insert(index)
        guard let first = visibleIndices.min(), let last = visibleIndices.max() else { return }
        Task { await viewModel.visibleRangeChanged(first...last) }
    }
}
