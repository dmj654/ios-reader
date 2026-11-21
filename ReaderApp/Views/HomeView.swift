//
//  HomeView.swift
//
//  主页：卡片墙。可见卡片按 HomeLayoutStore 持久化的顺序排列；
//  编辑态可拖动排序、隐藏与恢复；非编辑态点卡片跳转到对应页面。
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var settings: ReadingSettings
    @ObservedObject var sources: SourceStore
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject private var homeLayout: HomeLayoutStore
    @ObservedObject private var stats = ReadingStatsStore.shared

    var onOpenBook: (Book) -> Void
    var onOpenSettings: () -> Void
    var switchTab: (RootView.RootTab) -> Void
    var openHistory: () -> Void

    @Environment(\.editMode) private var editMode

    init(
        settings: ReadingSettings,
        sources: SourceStore,
        shelf: BookshelfViewModel,
        homeLayout: HomeLayoutStore = .shared,
        onOpenBook: @escaping (Book) -> Void,
        onOpenSettings: @escaping () -> Void,
        switchTab: @escaping (RootView.RootTab) -> Void,
        openHistory: @escaping () -> Void
    ) {
        self.settings = settings
        self.sources = sources
        self.shelf = shelf
        self.homeLayout = homeLayout
        self.onOpenBook = onOpenBook
        self.onOpenSettings = onOpenSettings
        self.switchTab = switchTab
        self.openHistory = openHistory
    }

    private var isEditing: Bool {
        editMode?.wrappedValue == .active
    }

    private var continueBook: Book? {
        HomeSummary.mostRecentBook(books: shelf.books)
    }

    private var localCovers: [Book] {
        HomeSummary.recentCovers(books: shelf.books, limit: 4)
    }

    private var historyCount: Int {
        HomeSummary.historyCount(books: shelf.books, stats: stats.books)
    }

    private var usableSourceCount: Int {
        HomeSummary.usableSourceCount(sources: sources.enabledSources)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(homeLayout.layout.order) { id in
                        visibleRow(id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onMove(perform: homeLayout.move)
                }

                if homeLayout.layout.hidden.isEmpty == false {
                    Section("已隐藏") {
                        ForEach(homeLayout.layout.hidden) { id in
                            hiddenRow(id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - 行

    private func visibleRow(_ id: HomeCardID) -> some View {
        HStack(spacing: 14) {
            iconBlock(id)

            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text(summary(for: id))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            trailing(for: id)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCard()
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing == false {
                handleTap(id)
            }
        }
    }

    private func iconBlock(_ id: HomeCardID) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.accentSoft)
            Image(systemName: id.iconName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppTheme.accent)
        }
        .frame(width: 40, height: 40)
    }

    private func hiddenRow(_ id: HomeCardID) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: id.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(id.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button {
                homeLayout.restore(id)
            } label: {
                Image(systemName: "eye")
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AppTheme.card.opacity(0.55),
            in: RoundedRectangle(cornerRadius: AppTheme.radiusInner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusInner, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 0.5)
        )
    }

    // MARK: - 摘要与跳转

    private func summary(for id: HomeCardID) -> String {
        switch id {
        case .continueReading:
            if let book = continueBook {
                return "读到 \(Int((book.progress * 100).rounded()))% · \(book.title)"
            }
            return "暂无在读"
        case .local:
            return "\(shelf.books.count) 本"
        case .history:
            return historyCount > 0 ? "\(historyCount) 条记录" : "还没有记录"
        case .sources:
            return "\(usableSourceCount) 个可用源"
        case .discover:
            return "书单与分类推荐"
        case .search:
            return "按书名 / 作者找书"
        }
    }

    @ViewBuilder
    private func trailing(for id: HomeCardID) -> some View {
        switch id {
        case .local:
            HStack(spacing: 6) {
                ForEach(localCovers) { book in
                    MiniCover(book: book)
                }
                Button {
                    startImport()
                } label: {
                    Label("导入", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        default:
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private func handleTap(_ id: HomeCardID) {
        switch id {
        case .continueReading:
            if let book = continueBook {
                onOpenBook(book)
            } else {
                switchTab(.shelf)
            }
        case .local:
            switchTab(.shelf)
        case .history:
            openHistory()
        case .sources:
            switchTab(.discover)
        case .discover:
            switchTab(.discover)
        case .search:
            switchTab(.search)
        }
    }

    private func startImport() {
        DocumentPickerHost.present(contentTypes: PickTypes.books, allowsMultiple: true) { urls in
            Task {
                for url in urls {
                    _ = await shelf.importBook(from: url)
                }
            }
        }
    }
}

// MARK: - 迷你封面

private struct MiniCover: View {
    let book: Book

    @State private var cover: UIImage?

    var body: some View {
        ZStack {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [book.format.tintColor.opacity(0.92), book.format.tintColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Text(initial)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .frame(width: 36, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task { loadCover() }
    }

    private var initial: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).isEmpty ? "书" : String(trimmed.prefix(1))
    }

    private func loadCover() {
        if let disk = CoverStore.cached(bookID: book.id) {
            cover = disk
            return
        }
        guard book.format != .txt else { return }
        Task.detached(priority: .utility) {
            let image = CoverStore.generate(url: book.absoluteURL, format: book.format, bookID: book.id)
            await MainActor.run { cover = image }
        }
    }
}
