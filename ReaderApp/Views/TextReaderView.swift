//
//  TextReaderView.swift
//  ReaderApp
//
//  TXT / EPUB 阅读页（v1.0）
//  - 分页由 CoreText 精确计算，正文宽度和渲染宽度一致
//  - EPUB 插图单独成页（不打断正文排版）
//  - 书签（按字符偏移存）与全文搜索
//  - 统一胶囊工具条（见 ReaderChrome.swift）
//  - 左边缘右滑退出阅读
//

import SwiftUI
import UIKit

// MARK: - 面板

enum ReaderPanel: String, CaseIterable, Identifiable {
    case toc, bookmarks, search

    var id: String { rawValue }

    var name: String {
        switch self {
        case .toc: return "目录"
        case .bookmarks: return "书签"
        case .search: return "搜索"
        }
    }
}

struct SearchHit: Identifiable {
    let id = UUID()
    let offset: Int
    let snippet: String
}

/// 一页：正文页（range）或插图页（imageFile）
struct TextPage: Identifiable {
    let id = UUID()
    let startOffset: Int
    let range: NSRange?
    let imageFile: String?
}

struct TextReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    let onExit: () -> Void

    @EnvironmentObject var shelf: BookshelfViewModel

    @State private var chapters: [Chapter] = []
    @State private var flatText = ""
    @State private var chapterStarts: [Int] = []
    @State private var imageAnchors: [BookText.ImageAnchor] = []
    @State private var pages: [TextPage] = []
    @State private var pageIndex = 0
    @State private var innerSize: CGSize = .zero
    @State private var isLoading = true
    @State private var didJump = false
    @State private var showMenu = false
    @State private var showPanels = false
    @State private var panelTab: ReaderPanel = .toc
    @State private var showSettings = false
    @State private var errorText: String?
    @State private var searchQuery = ""
    @State private var searchHits: [SearchHit] = []
    @State private var searching = false

    @ObservedObject private var speech = SpeechReader.shared

    private let hPad: CGFloat = 22
    private let vPad: CGFloat = 16

    /// 阅读统计（单例，主线程访问）
    private var stats: ReadingStatsStore { ReadingStatsStore.shared }

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            GeometryReader { geo in
                let contentSize = CGSize(
                    width: max(1, geo.size.width - hPad * 2),
                    height: max(1, geo.size.height - vPad * 2)
                )

                ZStack(alignment: .topLeading) {
                    if isLoading {
                        ProgressView("正在解析…")
                            .tint(settings.theme.foreground)
                            .foregroundStyle(settings.theme.foreground)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else if let errorText {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(errorText).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(settings.theme.foreground)
                        .padding(40)
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        pageContent(size: contentSize)
                            .padding(EdgeInsets(top: vPad, leading: hPad, bottom: vPad, trailing: hPad))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                                handleTap(at: point, in: contentSize)
                            }
                            .gesture(swipeGesture)
                            .animation(settings.pageTurn == .none ? nil : .easeInOut(duration: 0.18), value: pageIndex)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .onAppear {
                    if innerSize != contentSize {
                        innerSize = contentSize
                        repaginate(keepingOffset: true)
                    }
                }
                .onChange(of: contentSize) { _, newValue in
                    guard newValue != innerSize else { return }
                    innerSize = newValue
                    repaginate(keepingOffset: true)
                }
            }

            if showMenu {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .onChange(of: settings.fontSize) { _, _ in repaginate(keepingOffset: true) }
        .onChange(of: settings.lineSpacing) { _, _ in repaginate(keepingOffset: true) }
        .onChange(of: settings.fontName) { _, _ in repaginate(keepingOffset: true) }
        .onChange(of: settings.paragraphSpacing) { _, _ in repaginate(keepingOffset: true) }
        .onChange(of: settings.boldBody) { _, _ in repaginate(keepingOffset: true) }
        .onDisappear {
            speech.stop()
            saveProgress()
            stats.endSession()
        }
        .sheet(isPresented: $showPanels) { panelsSheet }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, shelf: shelf) }
    }

    // MARK: - 正文

    @ViewBuilder
    private func pageContent(size: CGSize) -> some View {
        if pages.isEmpty == false, pageIndex < pages.count {
            let page = pages[pageIndex]
            if let range = page.range {
                PageTextView(
                    attributedText: pageAttributedString(range),
                    theme: settings.theme
                )
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .id(pageIndex)
            } else if let file = page.imageFile {
                ReaderImageView(
                    path: imageDir.appendingPathComponent(file),
                    theme: settings.theme
                )
                .frame(width: size.width, height: size.height)
                .id(pageIndex)
            } else {
                Color.clear.frame(width: size.width, height: size.height)
            }
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    private func pageAttributedString(_ range: NSRange) -> NSAttributedString {
        let ns = flatText as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let rawSlice = ns.substring(with: clamped)
        let slice = TextScript.convert(rawSlice, mode: settings.scriptMode)
        let attrs = TextPaginator.attributes(
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            color: UIColor(settings.theme.foreground),
            fontName: settings.fontName,
            paragraphSpacing: settings.paragraphSpacing,
            bold: settings.boldBody
        )
        return NSAttributedString(string: slice, attributes: attrs)
    }

    private var imageDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookImages")
            .appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    // MARK: - 手势

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }

                // 屏幕左边缘往右划 → 退出阅读
                if value.startLocation.x < 44, dx > 70 {
                    saveProgress()
                    onExit()
                    return
                }

                if dx < -50 {
                    turn(by: 1)
                } else if dx > 50 {
                    turn(by: -1)
                }
            }
    }

    private func handleTap(at point: CGPoint, in size: CGSize) {
        stats.noteActivity()
        if showMenu {
            withAnimation { showMenu = false }
            return
        }
        let ratio = point.x / max(1, size.width)
        if ratio < 0.3 {
            turn(by: -1)
        } else if ratio > 0.7 {
            turn(by: 1)
        } else {
            withAnimation { showMenu = true }
        }
    }

    // MARK: - 工具条

    private var ink: Color { settings.theme.foreground }

    private var bookmarkActive: Bool {
        shelf.isBookmarked(bookID: book.id, offset: currentOffset)
    }

    private var menuOverlay: some View {
        VStack(spacing: 0) {
            ReaderCapsule(dark: settings.theme.isDark) {
                HStack(spacing: 2) {
                    ChromeIconButton(systemName: "chevron.left", tint: ink) {
                        saveProgress()
                        onExit()
                    }

                    Text(book.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    ChromeIconButton(
                        systemName: bookmarkActive ? "bookmark.fill" : "bookmark",
                        tint: ink
                    ) {
                        toggleBookmark()
                    }

                    Text(pageSummary)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ink.opacity(0.55))
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
            .padding(.top, ReaderChromeMetrics.topGap)

            Spacer(minLength: 0)

            ReaderCapsule(dark: settings.theme.isDark) {
                HStack(spacing: 0) {
                    ChromeIconButton(systemName: "list.bullet", tint: ink) {
                        panelTab = .toc
                        showPanels = true
                    }

                    ChromeProgressTrack(fraction: progressBinding, tint: ink) {
                        saveProgress()
                    }
                    .padding(.horizontal, 2)

                    Text("\(Int((pageFraction * 100).rounded()))%")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(ink.opacity(0.55))
                        .frame(minWidth: 30, alignment: .trailing)
                        .allowsHitTesting(false)

                    ChromeIconButton(systemName: "magnifyingglass", tint: ink) {
                        panelTab = .search
                        showPanels = true
                    }

                    ChromeIconButton(systemName: speech.speaking ? "speaker.wave.2.fill" : "speaker.wave.2", tint: ink) {
                        toggleSpeech()
                    }

                    ChromeIconButton(systemName: "textformat", tint: ink) {
                        showSettings = true
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
            .padding(.bottom, ReaderChromeMetrics.bottomGap)
        }
    }

    private var pageSummary: String {
        "\(min(pageIndex + 1, max(1, pages.count))) / \(max(1, pages.count))"
    }

    private var pageFraction: Double {
        guard pages.count > 1 else { return 0 }
        return Double(min(max(pageIndex, 0), pages.count - 1)) / Double(pages.count - 1)
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { pageFraction },
            set: { newValue in jump(toFraction: newValue) }
        )
    }

    private func jump(toFraction fraction: Double) {
        guard pages.isEmpty == false else { return }
        let span = Double(max(0, pages.count - 1))
        let index = Int((fraction * span).rounded())
        pageIndex = min(pages.count - 1, max(0, index))
    }

    // MARK: - 面板（目录 / 书签 / 搜索）

    private var panelsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $panelTab) {
                    ForEach(ReaderPanel.allCases) { item in
                        Text(item.name).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                switch panelTab {
                case .toc:
                    tocList
                case .bookmarks:
                    bookmarkList
                case .search:
                    searchPane
                }
            }
            .navigationTitle(panelTab.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showPanels = false }
                }
            }
            .onChange(of: panelTab) { _, newValue in
                if newValue == .search { runSearch() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tocList: some View {
        List {
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                Button {
                    jump(toChapter: index)
                    showPanels = false
                    showMenu = false
                } label: {
                    HStack {
                        Text(chapter.title).lineLimit(1)
                        Spacer()
                        if isCurrent(chapterIndex: index) {
                            Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var bookmarkList: some View {
        Group {
            if shelf.bookmarks(for: book.id).isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("还没有书签")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("阅读时点顶部工具条的书签图标即可添加")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                List {
                    ForEach(shelf.bookmarks(for: book.id)) { bookmark in
                        Button {
                            jump(toOffset: bookmark.offset)
                            showPanels = false
                            showMenu = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.chapter)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                Text(bookmark.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                shelf.removeBookmark(bookmark)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var searchPane: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索正文中的字词", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchQuery) { _, _ in runSearch() }
                if searchQuery.isEmpty == false {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            if searching {
                ProgressView().padding(.top, 20)
                Spacer()
            } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("输入关键词后会在整本书里查找，点结果直接跳过去")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                Spacer()
            } else if searchHits.isEmpty {
                Text("没有找到「\(searchQuery)」")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                Spacer()
            } else {
                List {
                    ForEach(searchHits) { hit in
                        Button {
                            jump(toOffset: hit.offset)
                            showPanels = false
                            showMenu = false
                        } label: {
                            Text(highlightedSnippet(hit.snippet))
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    /// 把命中词加粗，简单拼一下 AttributedString
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return attributed }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let found = attributed[searchStart...].range(of: needle, options: .caseInsensitive) {
            attributed[found].inlinePresentationIntent = .stronglyEmphasized
            searchStart = found.upperBound
        }
        return attributed
    }

    // MARK: - 目录 / 书签 / 搜索行为

    private var currentOffset: Int {
        guard pages.indices.contains(pageIndex) else { return 0 }
        return pages[pageIndex].startOffset
    }

    private func firstPageIndex(forOffset offset: Int) -> Int {
        guard pages.isEmpty == false else { return 0 }
        for (index, page) in pages.enumerated() {
            let length = max(1, page.range?.length ?? 1)
            if offset < page.startOffset + length {
                return index
            }
        }
        return pages.count - 1
    }

    private func jump(toOffset offset: Int) {
        guard pages.isEmpty == false else { return }
        pageIndex = firstPageIndex(forOffset: offset)
        stats.noteActivity()
        saveProgress()
    }

    private func turn(by delta: Int) {
        let target = pageIndex + delta
        guard pages.isEmpty == false, target >= 0, target < pages.count else { return }
        pageIndex = target
        stats.noteActivity(pages: 1)
        saveProgress()
    }

    private func jump(toChapter index: Int) {
        guard index < chapterStarts.count, pages.isEmpty == false else { return }
        jump(toOffset: chapterStarts[index])
    }

    private func isCurrent(chapterIndex index: Int) -> Bool {
        guard index < chapterStarts.count else { return false }
        let start = chapterStarts[index]
        let end = index + 1 < chapterStarts.count ? chapterStarts[index + 1] : Int.max
        let offset = currentOffset
        return offset >= start && offset < end
    }

    private func chapterTitle(for offset: Int) -> String {
        guard chapters.isEmpty == false else { return "全文" }
        var result = chapters[0].title
        for (index, start) in chapterStarts.enumerated() where index < chapters.count {
            if offset >= start { result = chapters[index].title } else { break }
        }
        return result
    }

    private func snippet(around offset: Int, length: Int = 52) -> String {
        let ns = flatText as NSString
        guard ns.length > 1 else { return "" }
        let start = max(0, min(offset - 4, ns.length - 1))
        let end = min(ns.length, start + length)
        let raw = ns.substring(with: NSRange(location: start, length: end - start))
        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleBookmark() {
        let offset = currentOffset
        shelf.toggleBookmark(
            bookID: book.id,
            offset: offset,
            chapter: chapterTitle(for: offset),
            snippet: snippet(around: offset)
        )
        if shelf.isBookmarked(bookID: book.id, offset: offset) {
            withAnimation { showMenu = true }
        }
    }

    /// 从当前位置读到本章结束（最多 6000 字），翻章后再点一次
    private func toggleSpeech() {
        if speech.speaking {
            speech.stop()
            return
        }
        let slice = speechSlice()
        guard slice.isEmpty == false else { return }
        speech.speak(slice, key: "\(book.id.uuidString)-\(currentOffset)")
    }

    private func speechSlice() -> String {
        let ns = flatText as NSString
        guard ns.length > 0 else { return "" }
        let start = max(0, min(currentOffset, ns.length - 1))

        var end = ns.length
        if chapterStarts.isEmpty == false {
            for index in chapterStarts.indices {
                let begin = chapterStarts[index]
                let finish = index + 1 < chapterStarts.count ? chapterStarts[index + 1] : ns.length
                if start >= begin, start < finish {
                    end = finish
                    break
                }
            }
        }
        end = min(end, start + 6000)
        end = min(max(end, start + 1), ns.length)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false, flatText.isEmpty == false else {
            searchHits = []
            return
        }
        let text = flatText
        searching = true

        Task {
            let hits = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                var results: [SearchHit] = []
                let ns = text as NSString
                var start = 0
                let limit = 200
                while start < ns.length, results.count < limit {
                    let remaining = NSRange(location: start, length: ns.length - start)
                    let found = ns.range(of: query, options: [.caseInsensitive], range: remaining)
                    if found.location == NSNotFound { break }

                    let contextStart = max(0, found.location - 20)
                    let contextEnd = min(ns.length, found.location + found.length + 36)
                    let context = ns.substring(
                        with: NSRange(location: contextStart, length: contextEnd - contextStart)
                    )
                    let cleaned = context
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    results.append(SearchHit(offset: found.location, snippet: cleaned))

                    let next = found.location + max(1, found.length)
                    if next >= ns.length { break }
                    start = next
                }
                return results
            }.value

            searchHits = hits
            searching = false
        }
    }

    // MARK: - 加载 / 分页 / 存盘

    @MainActor
    private func load() async {
        isLoading = true
        let url = book.absoluteURL
        let format = book.format
        let fallbackTitle = book.title
        let targetImageDir = imageDir
        let bookID = book.id

        let result: BookText? = await Task.detached(priority: .userInitiated) { () -> BookText? in
            // 先看解析缓存：同一本书第二次打开直接秒开
            if let cached = TextCache.load(bookID: bookID, source: url) {
                return cached
            }

            let parsed: BookText?
            switch format {
            case .txt:
                parsed = TextLoader.load(url: url, fallbackTitle: fallbackTitle)
            case .epub:
                parsed = EpubParser.load(url: url, imageDir: targetImageDir)
            default:
                parsed = nil
            }

            if let parsed {
                TextCache.save(parsed, bookID: bookID, source: url)
            }
            return parsed
        }.value

        guard let bookText = result else {
            errorText = "无法解析这本书，可能文件损坏或格式不支持。"
            isLoading = false
            return
        }

        chapters = bookText.chapters
        let flattenedContent = bookText.flattened()
        flatText = flattenedContent.text
        chapterStarts = flattenedContent.chapterStarts
        imageAnchors = flattenedContent.imageAnchors

        if book.format == .epub, bookText.title.isEmpty == false {
            shelf.updateTitle(
                bookID: book.id,
                title: bookText.title,
                author: bookText.author,
                total: flatText.utf16.count
            )
        } else if book.totalUnits <= 0, flatText.isEmpty == false {
            // TXT 导入时为了不读整本，总字数故意留空；第一次打开这里补上，进度条才准
            shelf.updateTitle(
                bookID: book.id,
                title: book.title,
                author: book.author,
                total: flatText.utf16.count
            )
        }

        isLoading = false
        repaginate(keepingOffset: false)
        stats.beginSession(bookID: book.id)
    }

    private func repaginate(keepingOffset: Bool) {
        guard flatText.isEmpty == false, innerSize.width > 20, innerSize.height > 20 else { return }

        let offset = keepingOffset ? currentOffset : book.location
        let attrs = TextPaginator.attributes(
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            color: UIColor(settings.theme.foreground),
            fontName: settings.fontName,
            paragraphSpacing: settings.paragraphSpacing,
            bold: settings.boldBody
        )

        let ns = flatText as NSString
        var built: [TextPage] = []
        var cursor = 0

        func appendTextPages(from start: Int, to end: Int) {
            guard end > start else { return }
            let segment = ns.substring(with: NSRange(location: start, length: end - start))
            let ranges = TextPaginator.paginate(segment, attributes: attrs, pageSize: innerSize)
            for range in ranges {
                built.append(
                    TextPage(
                        startOffset: start + range.location,
                        range: NSRange(location: start + range.location, length: range.length),
                        imageFile: nil
                    )
                )
            }
        }

        for anchor in imageAnchors {
            let cut = min(max(anchor.offset, cursor), ns.length)
            appendTextPages(from: cursor, to: cut)
            built.append(TextPage(startOffset: cut, range: nil, imageFile: anchor.file))
            cursor = max(cursor, cut)
        }
        appendTextPages(from: cursor, to: ns.length)

        if built.isEmpty {
            built = [TextPage(startOffset: 0, range: NSRange(location: 0, length: ns.length), imageFile: nil)]
        }

        pages = built
        pageIndex = firstPageIndex(forOffset: didJump ? offset : book.location)
        didJump = true
    }

    private func saveProgress() {
        let total = flatText.utf16.count
        shelf.updateProgress(bookID: book.id, location: currentOffset, totalUnits: total)
    }
}

// MARK: - 插图页

struct ReaderImageView: View {
    let path: URL
    let theme: ReaderTheme

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                    Text("插图文件不在了")
                        .font(.caption)
                }
                .foregroundStyle(theme.foreground.opacity(0.45))
            } else {
                ProgressView()
                    .tint(theme.foreground.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard image == nil, failed == false else { return }
            let url = path
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                UIImage(contentsOfFile: url.path)
            }.value
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}
