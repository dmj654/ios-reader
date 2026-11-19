//
//  TextReaderView.swift
//  ReaderApp
//
//  TXT / EPUB 阅读页：分页、翻页、目录、字号行距、主题、进度记忆
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

    var body: some View {
        GeometryReader { geo in
            let insets = EdgeInsets(
                top: geo.safeAreaInsets.top + 14,
                leading: 22,
                bottom: geo.safeAreaInsets.bottom + 14,
                trailing: 22
            )
            let contentSize = CGSize(
                width: max(1, geo.size.width - insets.leading - insets.trailing),
                height: max(1, geo.size.height - insets.top - insets.bottom)
            )

            ZStack {
                settings.theme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView("正在解析…")
                        .tint(settings.theme.foreground)
                        .foregroundStyle(settings.theme.foreground)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorText)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(settings.theme.foreground)
                    .padding(40)
                } else {
                    pageContent
                        .padding(insets)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1, coordinateSpace: .local) { point in
                            handleTap(at: point, in: contentSize)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    if value.translation.width < -40 {
                                        turn(by: 1)
                                    } else if value.translation.width > 40 {
                                        turn(by: -1)
                                    }
                                }
                        )
                        .animation(settings.pageTurn == .none ? nil : .easeInOut(duration: 0.18), value: pageIndex)
                }

                if showMenu {
                    menuOverlay(geo: geo)
                        .transition(.opacity)
                }
            }
            .onAppear {
                innerSize = contentSize
            }
            .onChange(of: contentSize) { _, newValue in
                innerSize = newValue
                repaginate(keepingOffset: true)
            }
        }
        .ignoresSafeArea()
        .task { await load() }
        .onChange(of: settings.fontSize) { _, _ in repaginate(keepingOffset: true) }
        .onChange(of: settings.lineSpacing) { _, _ in repaginate(keepingOffset: true) }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showTOC) { tocSheet }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
    }

    // MARK: - 正文渲染

    @ViewBuilder
    private var pageContent: some View {
        if pageIndex < pageRanges.count {
            PageTextView(
                attributedText: pageAttributedString(pageRanges[pageIndex]),
                theme: settings.theme
            )
            .id(pageIndex)
        } else {
            Color.clear
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

    // MARK: - 菜单

    private func menuOverlay(geo: GeometryProxy) -> some View {
        VStack {
            // 顶部
            HStack(spacing: 16) {
                Button {
                    saveProgress()
                    onExit()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                }
            }
            .foregroundStyle(settings.theme.foreground)
            .padding(.horizontal, 22)
            .padding(.top, geo.safeAreaInsets.top + 8)
            .padding(.bottom, 12)
            .background(settings.theme.background.opacity(0.96))

            Spacer()

            // 底部
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text("\(pageIndex + 1)")
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { Double(pageIndex) },
                            set: { newValue in
                                pageIndex = min(pageRanges.count - 1, max(0, Int(newValue)))
                            }
                        ),
                        in: 0...Double(max(1, pageRanges.count - 1))
                    )
                    Text("\(pageRanges.count)")
                        .font(.caption)
                }

                HStack(spacing: 28) {
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
                        HStack(spacing: 6) {
                            Image(systemName: "Aa")
                            Text("设置").font(.caption)
                        }
                    }
                }
                .font(.system(size: 18))
            }
            .foregroundStyle(settings.theme.foreground)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, geo.safeAreaInsets.bottom + 8)
            .background(settings.theme.background.opacity(0.96))
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
                            Text(chapter.title)
                                .lineLimit(1)
                            Spacer()
                            if isCurrent(chapterIndex: index) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.tint)
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
        if ratio < 0.28 {
            turn(by: -1)
        } else if ratio > 0.72 {
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

        // 顺手把书名补全（EPUB 内嵌了真实书名）
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
