//
//  ComicReaderView.swift
//  ReaderApp
//
//  漫画阅读（v0.6）：
//  - 相邻页预读，翻页基本不白屏
//  - 双指缩放 / 双击放大 / 放大后拖动
//  - 整页显示 或 铺满宽度 两种模式
//  - 阅读方向可切换（左→右 / 右→左）
//  - 缩略图页目录，直接跳页
//  - 进度条、页码、进度记忆
//  - 左边缘往右划退出
//

import SwiftUI
import UIKit

struct ComicReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    let onExit: () -> Void

    @EnvironmentObject var shelf: BookshelfViewModel

    @State private var pagePaths: [String] = []
    @State private var pageIndex: Int = 0
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var showMenu = false
    @State private var showGrid = false
    @State private var showSettings = false
    @State private var zoomed = false
    @State private var imageLoading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("正在读取漫画…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if pagePaths.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                    Text("这本书里没有找到图片")
                    Text("可能是压缩包里的图片格式不受支持")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                .foregroundStyle(.white)
                .padding(40)
                .multilineTextAlignment(.center)
            } else {
                ComicPageView(
                    image: image,
                    fitWidth: settings.comicFitWidth,
                    onSingleTap: { ratio in handleTap(ratio: ratio) },
                    onSwipeLeft: { turnTowardNext() },
                    onSwipeRight: { turnTowardPrev() },
                    onZoomChanged: { zoomed = $0 }
                )
                .ignoresSafeArea()

                if imageLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }

                // 页码指示（无菜单时的一小行）
                if showMenu == false {
                    VStack {
                        Spacer()
                        Text("\(pageIndex + 1) / \(pagePaths.count)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.bottom, 6)
                    }
                    .allowsHitTesting(false)
                }
            }

            if showMenu {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showGrid) { gridSheet }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(pageIndex + 1) / \(pagePaths.count)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    showGrid = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 17))
                        .frame(width: 30, height: 30, alignment: .trailing)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background { Color.black.opacity(0.85).ignoresSafeArea(edges: .top) }

            Spacer()

            VStack(spacing: 14) {
                Slider(
                    value: Binding(
                        get: { Double(pageIndex) },
                        set: { newValue in
                            let target = min(pagePaths.count - 1, max(0, Int(newValue)))
                            if target != pageIndex { jump(to: target) }
                        }
                    ),
                    in: 0...Double(max(1, pagePaths.count - 1))
                )
                .tint(.white)

                HStack(spacing: 10) {
                    chip(settings.comicFitWidth ? "铺满宽度" : "整页显示") {
                        settings.comicFitWidth.toggle()
                    }
                    chip(settings.comicRTL ? "右→左" : "左→右") {
                        settings.comicRTL.toggle()
                    }
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17))
                            .frame(width: 34, height: 30)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background { Color.black.opacity(0.85).ignoresSafeArea(edges: .bottom) }
        }
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 页目录

    private var gridSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(Array(pagePaths.enumerated()), id: \.offset) { index, path in
                        Button {
                            jump(to: index)
                            showGrid = false
                        } label: {
                            ComicThumbView(
                                path: path,
                                url: book.absoluteURL,
                                number: index + 1,
                                isCurrent: index == pageIndex
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .navigationTitle("共 \(pagePaths.count) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showGrid = false }
                }
            }
        }
    }

    // MARK: - 逻辑

    @MainActor
    private func load() async {
        isLoading = true
        let url = book.absoluteURL

        let paths = await Task.detached(priority: .userInitiated) { () -> [String] in
            ComicLoader.listPages(url: url)
        }.value

        pagePaths = paths
        pageIndex = min(max(0, book.location), max(0, paths.count - 1))
        isLoading = false

        if paths.isEmpty == false {
            await showPage(pageIndex)
            shelf.updateProgress(bookID: book.id, location: pageIndex, totalUnits: paths.count)
        }
    }

    @MainActor
    private func showPage(_ index: Int) async {
        guard pagePaths.indices.contains(index) else { return }
        let path = pagePaths[index]
        let url = book.absoluteURL

        if let hit = ComicLoader.cachedImage(at: path, in: url) {
            image = hit
            imageLoading = false
        } else {
            imageLoading = true
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                ComicLoader.image(at: path, in: url)
            }.value
            if pageIndex == index {
                image = loaded
                imageLoading = false
            }
        }
        preload(around: index)
    }

    /// 预读前后各一页（+2），翻页时不至于白一下
    private func preload(around index: Int) {
        let url = book.absoluteURL
        for offset in [1, 2, -1] {
            let target = index + offset
            guard pagePaths.indices.contains(target) else { continue }
            let path = pagePaths[target]
            guard ComicLoader.cached(path: path, url: url) == false else { continue }
            Task.detached(priority: .utility) { _ = ComicLoader.image(at: path, in: url) }
        }
    }

    private func jump(to index: Int) {
        guard pagePaths.indices.contains(index) else { return }
        pageIndex = index
        saveProgress()
        Task { await showPage(index) }
    }

    private func turnTowardNext() {
        turn(by: settings.comicRTL ? -1 : 1)
    }

    private func turnTowardPrev() {
        turn(by: settings.comicRTL ? 1 : -1)
    }

    private func turn(by delta: Int) {
        let target = pageIndex + delta
        guard pagePaths.indices.contains(target) else { return }
        pageIndex = target
        saveProgress()
        Task { await showPage(target) }
    }

    /// 点按区域：左 1/3 翻向"前"，右 1/3 翻向"后"，中间叫菜单
    private func handleTap(ratio: CGFloat) {
        if showMenu {
            withAnimation { showMenu = false }
            return
        }
        if zoomed { return }
        if ratio < 0.32 {
            turnTowardPrev()
        } else if ratio > 0.68 {
            turnTowardNext()
        } else {
            withAnimation { showMenu = true }
        }
    }

    private func saveProgress() {
        guard pagePaths.isEmpty == false else { return }
        shelf.updateProgress(bookID: book.id, location: pageIndex, totalUnits: pagePaths.count)
    }
}

// MARK: - 目录缩略图

struct ComicThumbView: View {
    let path: String
    let url: URL
    let number: Int
    let isCurrent: Bool

    @State private var thumb: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.white.opacity(0.08))
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().tint(.gray)
            }
            Text("\(number)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(5)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isCurrent ? 2 : 0.5)
        )
        .task {
            guard thumb == nil else { return }
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                ComicLoader.thumbnail(at: path, in: url)
            }.value
            thumb = loaded
        }
    }
}
