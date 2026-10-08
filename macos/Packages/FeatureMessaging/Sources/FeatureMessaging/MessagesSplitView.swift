import SwiftUI
import TandemDesign

/// The main window's Messages section (ui-spec §7.1): the thread list with search on the left and
/// the selected conversation with its composer on the right. Keeps showing the cached threads
/// while the phone is offline, with the composer disabled.
public struct MessagesSplitView: View {
    @Bindable private var viewModel: ThreadListViewModel
    private let makeConversation: @MainActor (ThreadRow) -> ConversationViewModel
    private let headerAccessory: (@MainActor (String) -> AnyView)?
    private let offlineComposerText: String?
    private let refreshTick: Int

    @State private var selectedThreadId: Int64?
    @State private var conversation: ConversationViewModel?

    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - offlineComposerText: non-nil while the phone is offline ("Sends when Pixel 9 is back").
    ///   - refreshTick: changing it reloads the thread list and the open conversation.
    public init(
        viewModel: ThreadListViewModel,
        makeConversation: @escaping @MainActor (ThreadRow) -> ConversationViewModel,
        headerAccessory: (@MainActor (String) -> AnyView)? = nil,
        offlineComposerText: String? = nil,
        refreshTick: Int = 0
    ) {
        self.viewModel = viewModel
        self.makeConversation = makeConversation
        self.headerAccessory = headerAccessory
        self.offlineComposerText = offlineComposerText
        self.refreshTick = refreshTick
    }

    public var body: some View {
        if viewModel.state == .permissionRequired {
            SectionEmptyState(kind: .turnedOffOnPhone, identifier: "threadListPermissionRequired")
        } else {
            HStack(spacing: 0) {
                list
                    .frame(width: 300)
                Divider()
                detail
            }
            .task(id: refreshTick) {
                await viewModel.reload()
                await conversation?.reload()
                if selectedThreadId == nil, let first = viewModel.visibleRows.first {
                    select(first)
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Messages.", state: stateText, size: 26)
            searchField
            content
        }
        .padding([.top, .horizontal], TandemSpacing.windowPadding - TandemSpacing.small)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var stateText: String {
        if offlineComposerText != nil { return "Offline." }
        return viewModel.unreadCount > 0 ? "\(viewModel.unreadCount) unread." : "All read."
    }

    private var searchField: some View {
        HStack(spacing: TandemSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TandemColor.ink2)
            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .tandemTextStyle(TandemTypography.body())
                .accessibilityIdentifier("threadSearchField")
        }
        .padding(.vertical, TandemSpacing.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            note("Loading messages.", identifier: "threadListLoading")
        case .empty:
            note("No conversations yet.", identifier: "threadListEmpty")
        case .permissionRequired:
            EmptyView()
        case .loaded:
            if viewModel.visibleRows.isEmpty {
                note("No matches.", identifier: "threadListNoMatches")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.visibleRows) { row in
                            threadRow(row)
                        }
                    }
                }
                .accessibilityIdentifier("threadList")
            }
        }
    }

    private func note(_ text: String, identifier: String) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.body())
            .foregroundStyle(TandemColor.ink2)
            .accessibilityIdentifier(identifier)
    }

    private func threadRow(_ row: ThreadRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: TandemSpacing.small) {
                if row.isUnread {
                    Circle().fill(TandemColor.ink).frame(width: 6, height: 6)
                        .accessibilityLabel("\(row.unreadBadge ?? "") unread")
                }
                Text(row.title)
                    .tandemTextStyle(row.isUnread ? TandemTypography.rowTitle() : TandemTypography.body(size: 16))
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
                Spacer()
                Text(row.timeText())
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
            }
            Text(row.snippet)
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
                .lineLimit(1)
        }
        .padding(.vertical, TandemSpacing.small + TandemSpacing.extraSmall)
        .padding(.horizontal, TandemSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: TandemSpacing.small)
                .fill(selectedThreadId == row.id ? TandemColor.ink.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { select(row) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("threadRow-\(row.id)")
    }

    @ViewBuilder
    private var detail: some View {
        if let conversation {
            ConversationView(
                viewModel: conversation,
                headerAccessory: headerAccessory,
                offlineComposerText: offlineComposerText
            )
            .id(selectedThreadId)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func select(_ row: ThreadRow) {
        selectedThreadId = row.id
        conversation = makeConversation(row)
    }
}
