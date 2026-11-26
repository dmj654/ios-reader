//
//  HomeView.swift
//
//  今日页：正在读主卡 + 三格统计 + 最近更新 + 夜读一句；
//  下面保留可排序的入口卡片（HomeLayoutStore 持久化）。
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var settings: ReadingSettings
    @ObservedObject var sources: SourceStore
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject private var homeLayout: HomeLayoutStore
    @ObservedObject private var stats = ReadingStatsStore.shared

    var onOpenBook: (Book) -> Void
    var onOpenSettings: () -> Void
    var switchTab: (AppTab) -> Void
    var openHistory: () -> Void

    @Environment(\.editMode) private var editMode

    init(
        settings: ReadingSettings,
        sources: SourceStore,
        shelf: BookshelfViewModel,
        homeLayout: HomeLayoutStore = .shared,
        onOpenBook: @escaping (Book) -> Void,
        onOpenSettings: @escaping () -> Void,
        switchTab: @escaping (AppTab) -> Void,
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

    private var recentBooks: [Book] {
        shelf.books
            .sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
            .prefix(3)
            .map { $0 }
    }

    private var readingCount: Int {
        shelf.books.filter { $0.isRead == false }.count
    }

    private var summary: StatsSummary {
        stats.summary(goalMinutes: 30)
    }

    private var weekHoursText: String {
        let hours = Double(summary.weekSeconds) / 3600
        if hours <= 0 { return "—" }
        return String(format: "%.1fh", hours)
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
                    heroSection
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))

                    statsStrip
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

                    sectionLabel("最近更新", trailing: recentBooks.isEmpty ? nil : "\(recentBooks.count) 本")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 0, trailing: 16))

                    updateCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))

                    quoteCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
                }

                Section {
                    ForEach(homeLayout.layout.order) { id in
                        visibleRow(id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onMove(perform: { from, to in
                        homeLayout.move(fromOffsets: from, toOffset: to)
                    })
                } header: {
                    sectionLabel("入口")
                        .textCase(nil)
                        .padding(.top, 16)
                }

                if homeLayout.layout.hidden.isEmpty == false {
                    Section {
                        ForEach(homeLayout.layout.hidden) { id in
                            hiddenRow(id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } header: {
                        sectionLabel("已隐藏").textCase(nil)
                    }
                }

                Section {
                    Color.clear.frame(height: 8)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("墨本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .tint(AppTheme.accent)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        switchTab(.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .tint(AppTheme.accent)
        }
    }

    // MARK: - 顶部区块

    @ViewBuilder
    private var heroSection: some View {
        if let book = continueBook {
            HeroCard(book: book) { onOpenBook(book) }
        } else {
            Button {
                switchTab(.shelf)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.accentSoft)
                        Image(systemName: "book.closed")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .frame(width: 100, height: 140)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有在读的书")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(AppTheme.primary)
                        Text("导入 TXT / EPUB，或从书源找一本")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondary)
                        Text("去书架")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .appCard(radius: 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell("\(readingCount)", "在读")
            divider
            statCell(weekHoursText, "本周")
            divider
            statCell("\(summary.streak)", "连续天数")
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .appCard(radius: 16)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.stroke)
            .frame(width: 1, height: 28)
    }

    private func sectionLabel(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondary)
            }
        }
    }

    @ViewBuilder
    private var updateCard: some View {
        VStack(spacing: 0) {
            if recentBooks.isEmpty {
                Text("书架还是空的")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(recentBooks.enumerated()), id: \.element.id) { index, book in
                    Button {
                        onOpenBook(book)
                    } label: {
                        HStack(spacing: 11) {
                            BookArtView(book: book, width: 36, height: 50, radius: 6, titleSize: 10)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.primary)
                                    .lineLimit(1)
                                Text(updateSubtitle(book))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AppTheme.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Text(updateTag(book))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(book.hasUpdate ? AppTheme.accent : AppTheme.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 66)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < recentBooks.count - 1 {
                        Rectangle()
                            .fill(AppTheme.stroke)
                            .frame(height: 1)
                            .padding(.leading, 59)
                    }
                }
            }
        }
        .appCard(radius: 16)
    }

    private func updateSubtitle(_ book: Book) -> String {
        if let chapter = book.latestChapter, chapter.isEmpty == false {
            return chapter
        }
        if book.progress > 0.005 {
            return "读到 \(Int((book.progress * 100).rounded()))% · \(book.format.rawValue)"
        }
        return "\(book.format.rawValue) · 未开始"
    }

    private func updateTag(_ book: Book) -> String {
        if book.hasUpdate { return "更新" }
        if book.isRead { return "已读" }
        return "在读"
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("夜里读到的句子，会在第二天早上留下来。")
                .font(.system(size: 13, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(AppTheme.primary.opacity(0.86))
            Text("墨本 · 夜读")
                .font(.system(size: 10))
                .tracking(1.6)
                .foregroundStyle(AppTheme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .appCard(radius: 16)
    }

    // MARK: - 入口行

    private func visibleRow(_ id: HomeCardID) -> some View {
        HStack(spacing: 14) {
            iconBlock(id)

            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text(summary(for: id))
                    .font(.system(size: 12))
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
                    .fill(AppTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.stroke, lineWidth: 0.5))
                Image(systemName: id.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                Text(id.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiary)
            }
            Spacer(minLength: 0)
            Button {
                homeLayout.restore(id)
            } label: {
                Image(systemName: "eye")
            }
            .foregroundStyle(AppTheme.secondary)
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
                .tint(AppTheme.accent)
            }
        default:
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiary)
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

// MARK: - 正在读主卡

private struct HeroCard: View {
    let book: Book
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                BookArtView(book: book, width: 100, height: 140, radius: 10, titleSize: 15)

                VStack(alignment: .leading, spacing: 0) {
                    Text(book.title)
                        .font(.system(size: 26, weight: .heavy, design: .serif))
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text("\(book.author) · \(book.format.rawValue)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondary)
                        .padding(.top, 5)

                    Spacer(minLength: 10)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppTheme.stroke)
                                .frame(height: 4)
                            Capsule()
                                .fill(AppTheme.accent)
                                .frame(width: max(4, geo.size.width * book.progress), height: 4)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text("\(Int((book.progress * 100).rounded()))% · \(progressText)")
                        Spacer(minLength: 0)
                        Text(remainText)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.top, 7)

                    Text("继续读")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AppTheme.accent, in: Capsule())
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private var progressText: String {
        if book.format == .comic || book.format == .pdf {
            return "第 \(min(book.location + 1, max(1, book.totalUnits))) 页"
        }
        return "读至 \(book.location) 字"
    }

    private var remainText: String {
        let left = max(0, book.totalUnits - book.location)
        if book.format == .comic || book.format == .pdf {
            return "剩 \(left) 页"
        }
        return "剩 \(left) 字"
    }
}

// MARK: - 封面（真实封面优先，否则墨色竖排）

struct BookArtView: View {
    let book: Book
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = 10
    var titleSize: CGFloat = 15

    @State private var cover: UIImage?

    var body: some View {
        ZStack {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                AppTheme.inkCover
                verticalTitle
                VStack {
                    Spacer()
                    HStack {
                        Rectangle()
                            .fill(AppTheme.seal)
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task { loadCover() }
    }

    private var verticalTitle: some View {
        VStack(spacing: 1) {
            ForEach(Array(book.title.prefix(8)).indices, id: \.self) { index in
                let chars = Array(book.title)
                Text(String(chars[index]))
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.96))
            }
        }
        .fixedSize()
    }

    private func loadCover() {
        if let disk = CoverStore.cached(bookID: book.id) {
            cover = disk
            return
        }
        guard book.format != .txt else { return }
        let url = book.absoluteURL
        let format = book.format
        let id = book.id
        Task.detached(priority: .utility) {
            let image = CoverStore.generate(url: url, format: format, bookID: id)
            await MainActor.run { cover = image }
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
