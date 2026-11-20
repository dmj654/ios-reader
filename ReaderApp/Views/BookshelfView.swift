//
//  BookshelfView.swift
//  ReaderApp
//
//  书架首页（v0.8）：封面网格 + 分组胶囊 + 搜索 + 真实封面（自动抽第一页）
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 分组

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all, novel, comic, recent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: return "全部"
        case .novel: return "小说"
        case .comic: return "漫画"
        case .recent: return "最近"
        }
    }
}

enum ShelfSort: String, CaseIterable, Identifiable {
    case recentRead, recentAdded, title, progress

    var id: String { rawValue }

    var name: String {
        switch self {
        case .recentRead: return "最近阅读"
        case .recentAdded: return "最近添加"
        case .title: return "书名"
        case .progress: return "阅读进度"
        }
    }
}

struct BookshelfView: View {
    @EnvironmentObject var shelf: BookshelfViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = ReadingSettings()
    @StateObject private var sources = SourceStore()

    @State private var showPicker = false
    @State private var showSources = false
    @State private var selectedBook: Book?
    @State private var showSettings = false
    @State private var toast: String?

    @State private var query = ""
    @State private var searchActive = false
    @State private var filter: ShelfFilter = .all
    @State private var coverVersion = 0
    @AppStorage("shelfSort") private var sortRaw = ShelfSort.recentRead.rawValue
    @State private var importing = false
    @State private var importDone = 0
    @State private var importTotal = 0
    @State private var renameBook: Book?
    @State private var renameText = ""

    private var sort: ShelfSort { ShelfSort(rawValue: sortRaw) ?? .recentRead }

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 132), spacing: 14, alignment: .top)]

    var body: some View {
        NavigationStack {
            ZStack {
                if shelf.books.isEmpty {
                    emptyState
                } else {
                    content
                }
                if let toast {
                    toastView(toast)
                }
                if importing {
                    importOverlay
                }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        searchActive = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Menu {
                        ForEach(ShelfSort.allCases) { item in
                            Button {
                                sortRaw = item.rawValue
                            } label: {
                                if sort == item {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSources = true
                    } label: {
                        Image(systemName: "globe")
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
            .searchable(text: $query, isPresented: $searchActive, prompt: "搜索书名")
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: pickTypes, allowsMultiple: true) { urls in
                    showPicker = false
                    guard urls.isEmpty == false else { return }
                    Task {
                        importing = true
                        importTotal = urls.count
                        importDone = 0
                        var failures: [String] = []
                        for url in urls {
                            if let error = await shelf.importBook(from: url) {
                                failures.append(error)
                            }
                            importDone += 1
                        }
                        importing = false
                        if failures.isEmpty {
                            show("已导入 \(urls.count) 个文件")
                        } else if failures.count == urls.count {
                            show("导入失败：\(failures[0])")
                        } else {
                            show("导入 \(urls.count - failures.count) 个，失败 \(failures.count) 个：\(failures[0])")
                        }
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { shelf.alertMessage != nil },
                set: { if $0 == false { shelf.alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(shelf.alertMessage ?? "")
            }
            .alert("重命名", isPresented: Binding(
                get: { renameBook != nil },
                set: { if $0 == false { renameBook = nil } }
            )) {
                TextField("书名", text: $renameText)
                Button("取消", role: .cancel) { renameBook = nil }
                Button("保存") {
                    if let book = renameBook {
                        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if name.isEmpty == false {
                            shelf.updateTitle(bookID: book.id, title: name, author: book.author, total: 0)
                        }
                    }
                    renameBook = nil
                }
            } message: {
                Text("只改显示的书名，不影响文件")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .sheet(isPresented: $showSources) {
                SourceSearchView(shelf: shelf, store: sources) { book in
                    showSources = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedBook = book
                    }
                }
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderView(book: book, settings: settings)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { shelf.scan() }
            }
            .onAppear { shelf.scan() }
        }
    }

    private var pickTypes: [UTType] {
        var types: [UTType] = [.item]
        types.append(.plainText)
        types.append(.pdf)
        types.append(.zip)
        for ext in ["epub", "cbz", "txt"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    // MARK: - 主体

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterBar

                if visibleBooks.isEmpty {
                    VStack(spacing: 8) {
                        Text(query.isEmpty ? "这个分组里还没有书" : "没有匹配「\(query)」的书")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visibleBooks) { book in
                            Button {
                                selectedBook = book
                            } label: {
                                CoverCell(book: book, version: coverVersion)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    selectedBook = book
                                } label: {
                                    Label("继续阅读", systemImage: "book")
                                }
                                Button {
                                    CoverStore.clear(bookID: book.id)
                                    coverVersion += 1
                                    show("正在重新生成封面")
                                } label: {
                                    Label("重新生成封面", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button {
                                    renameText = book.title
                                    renameBook = book
                                } label: {
                                    Label("重命名", systemImage: "character.cursor.ibeam")
                                }
                                Button(role: .destructive) {
                                    CoverStore.clear(bookID: book.id)
                                    shelf.delete(book)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 24)
        }
        .refreshable { shelf.scan() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShelfFilter.allCases) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { filter = item }
                    } label: {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(filter == item ? Color.white : Color.secondary)
                            .background(
                                Capsule().fill(
                                    filter == item
                                        ? Color.primary.opacity(0.88)
                                        : Color(uiColor: .secondarySystemBackground)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var visibleBooks: [Book] {
        var list = shelf.books

        switch filter {
        case .all:
            break
        case .novel:
            list = list.filter { $0.format != .comic }
        case .comic:
            list = list.filter { $0.format == .comic }
        case .recent:
            list = list.filter { $0.lastReadAt != nil }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        }

        switch sort {
        case .recentRead:
            return list.sorted { lhs, rhs in
                (lhs.lastReadAt ?? lhs.addedAt) > (rhs.lastReadAt ?? rhs.addedAt)
            }
        case .recentAdded:
            return list.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress:
            return list.sorted { lhs, rhs in
                if lhs.isRead != rhs.isRead { return rhs.isRead }
                return lhs.progress > rhs.progress
            }
        }
    }

    // MARK: - 空书架

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 70)

                Text("书架是空的")
                    .font(.title3.weight(.medium))

                Text("支持 TXT / EPUB / PDF / CBZ 漫画")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("点右上角 +，从「文件」里选书", systemImage: "plus.circle")
                    Label("或放进「文件」→ 我的 iPhone → 本地阅读器", systemImage: "folder")
                    Label("点地球按钮，用书源在线找书后下载到本地", systemImage: "globe")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
        .refreshable { shelf.scan() }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { toast = nil }
        }
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
        }
        .transition(.opacity)
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(importTotal > 1 ? "正在导入 \(min(importDone + 1, importTotal)) / \(importTotal)" : "正在导入…")
                    .font(.footnote)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }
}

// MARK: - 封面格

struct CoverCell: View {
    let book: Book
    let version: Int

    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                coverLayer

                if book.progress > 0.01 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.28))
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: max(2, geo.size.width * book.progress))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )

            Text(book.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task(id: version) { await loadCover() }
    }

    private var coverLayer: some View {
        ZStack {
            if let cover {
                Color.clear
                    .overlay {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    }
            } else {
                LinearGradient(
                    colors: [book.format.tintColor.opacity(0.92), book.format.tintColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Text(initial)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .clipped()
    }

    private var initial: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).isEmpty ? "书" : String(trimmed.prefix(1))
    }

    private var subtitle: String {
        if book.isRead { return "已读完 · \(book.format.rawValue)" }
        if book.progress > 0.005 { return "\(Int((book.progress * 100).rounded()))% · \(book.format.rawValue)" }
        return "未开始 · \(book.format.rawValue)"
    }

    private func loadCover() async {
        if let disk = CoverStore.cached(bookID: book.id) {
            cover = disk
            return
        }
        guard book.format != .txt else { return }

        let url = book.absoluteURL
        let format = book.format
        let id = book.id
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            CoverStore.generate(url: url, format: format, bookID: id)
        }.value

        if let image {
            cover = image
        }
    }
}
