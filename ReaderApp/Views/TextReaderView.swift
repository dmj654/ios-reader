//
//  TextReaderView.swift
//  ReaderApp
//
//  TXT / EPUB 阅读页：分页、翻页、目录、字号行距、主题、进度记忆
//
//  v0.5 修复：
//  1. 正文以前超出屏幕右边（一行的末尾被切掉）—— 现在严格按可用宽度计算和渲染
//  2. 顶部返回按钮压在状态栏上 —— 现在整个页面遵守安全区
//  3. 左边缘向右划直接退出阅读
//

import SwiftUI
import UIKit

struct TextReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    let onExit: () -> Void

    @EnvironmentObject var shelf: BookshelfViewModel

    @State private var chapters: [Chapter] = []
    @State private var flatText: String = ""
    @State private var chapterStarts: [Int] = []
    @State private var pageRanges: [NSRange] = []
    @State private var pageIndex: Int = 0
    @State private var innerSize: CGSize = .zero
    @State private var isLoading = true
    @State private var didJump = false
    @State private var showMenu = false
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var errorText: String?

    /// 正文四周留白
    private let hPad: CGFloat = 22
    private let vPad: CGFloat = 16

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
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showTOC) { tocSheet }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
    }

    // MARK: - 正文

    @ViewBuilder
    private func pageContent(size: CGSize) -> some View {
        if pageRanges.isEmpty == false, pageIndex < pageRanges.count {
            PageTextView(
                attributedText: pageAttributedString(pageRanges[pageIndex]),
                theme: settings.theme
            )
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .id(pageIndex)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    private func pageAttributedString(_ range: NSRange) -> NSAttributedString {
        let ns = flatText as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let slice = ns.substring(with: clamped)
        let attrs = TextPaginator.attributes(
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            color: UIColor(settings.theme.foreground)
        )
        return NSAttributedString(string: slice, attributes: attrs)
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

    // MARK: - 菜单

    private var menuOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    saveProgress()
                    onExit()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 30, height: 30, alignment: .leading)
                }
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17))
                        .frame(width: 30, height: 30, alignment: .trailing)
                }
            }
            .foregroundStyle(settings.theme.foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                settings.theme.background.opacity(0.97)
                    .ignoresSafeArea(edges: .top)
            )

            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text("\(pageIndex + 1)").font(.caption).monospacedDigit()
                    Slider(
                        value: Binding(
                            get: { Double(pageIndex) },
                            set: { newValue in
                                guard pageRanges.isEmpty == false else { return }
                                pageIndex = min(pageRanges.count - 1, max(0, Int(newValue)))
                            }
                        ),
                        in: 0...Double(max(1, pageRanges.count - 1))
                    )
                    Text("\(pageRanges.count)").font(.caption).monospacedDigit()
                }

                HStack(spacing: 26) {
                    Button {
                        settings.fontSize = max(13, settings.fontSize - 1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    Button {
                        settings.fontSize = min(30, settings.fontSize + 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "textformat")
                            Text("设置").font(.caption)
                        }
                    }
                }
                .font(.system(size: 18))
            }
            .foregroundStyle(settings.theme.foreground)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(
                settings.theme.background.opacity(0.97)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - 目录

    private var tocSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        jump(toChapter: index)
                        showTOC = false
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
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showTOC = false }
                }
            }
        }
    }

    // MARK: - 交互

    private func handleTap(at point: CGPoint, in size: CGSize) {
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

    private func turn(by delta: Int) {
        let target = pageIndex + delta
        guard pageRanges.isEmpty == false, target >= 0, target < pageRanges.count else { return }
        pageIndex = target
        saveProgress()
    }

    private func jump(toChapter index: Int) {
        guard index < chapterStarts.count, pageRanges.isEmpty == false else { return }
        let offset = chapterStarts[index]
        pageIndex = TextPaginator.pageIndex(for: offset, in: pageRanges)
        saveProgress()
    }

    private func isCurrent(chapterIndex index: Int) -> Bool {
        guard index < chapterStarts.count else { return false }
        let start = chapterStarts[index]
        let end = index + 1 < chapterStarts.count ? chapterStarts[index + 1] : Int.max
        let current = currentOffset
        return current >= start && current < end
    }

    private var currentOffset: Int {
        guard pageIndex < pageRanges.count else { return 0 }
        return pageRanges[pageIndex].location
    }

    // MARK: - 加载 / 分页 / 存盘

    @MainActor
    private func load() async {
        isLoading = true
        let url = book.absoluteURL
        let format = book.format
        let fallbackTitle = book.title

        let result: BookText? = await Task.detached(priority: .userInitiated) { () -> BookText? in
            switch format {
            case .txt:
                return TextLoader.load(url: url, fallbackTitle: fallbackTitle)
            case .epub:
                return EpubParser.load(url: url)
            default:
                return nil
            }
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

        if book.format == .epub, bookText.title.isEmpty == false {
            shelf.updateTitle(bookID: book.id, title: bookText.title, author: bookText.author, total: flatText.utf16.count)
        }

        isLoading = false
        repaginate(keepingOffset: false)
    }

    private func repaginate(keepingOffset: Bool) {
        guard flatText.isEmpty == false, innerSize.width > 20, innerSize.height > 20 else { return }

        let offset = keepingOffset ? currentOffset : book.location

        let attrs = TextPaginator.attributes(
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            color: UIColor(settings.theme.foreground)
        )
        pageRanges = TextPaginator.paginate(flatText, attributes: attrs, pageSize: innerSize)
        pageIndex = TextPaginator.pageIndex(for: offset, in: pageRanges)

        if didJump == false {
            pageIndex = TextPaginator.pageIndex(for: book.location, in: pageRanges)
            didJump = true
        }
    }

    private func saveProgress() {
        let total = flatText.utf16.count
        shelf.updateProgress(bookID: book.id, location: currentOffset, totalUnits: total)
    }
}
