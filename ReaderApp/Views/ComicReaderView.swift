//
//  ComicReaderView.swift
//  ReaderApp
//
//  漫画阅读（v0.7，全可配置）：
//  - 分页翻页 / 竖向连续滚动 两种阅读方式
//  - 适应屏幕 / 适应宽度 / 适应高度 三种适配
//  - 左→右 / 右→左 阅读方向
//  - 底部常驻工具条（目录 / 页码 / 翻页 / 进度线 / 设置），可常驻、可点按显隐
//  - 点按区域、双击放大、自动裁白边、压暗、屏幕常亮、预读页数 全可调
//  - 缩略图目录、进度记忆、左边缘右滑退出
//

import SwiftUI
import UIKit

struct ComicReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    let onExit: () -> Void

    @EnvironmentObject var shelf: BookshelfViewModel

    @State private var pagePaths: [String] = []
    @State private var pageIndex = 0
    @State private var visibleIndex = 0
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var imageLoading = false
    @State private var chromeVisible = false
    @State private var showGrid = false
    @State private var showSettings = false
    @State private var zoomed = false
    @State private var hideItem: DispatchWorkItem?
    @State private var scrollTarget: Int?
    /// 翻页缓冲：上一页盖在上层淡出，露出新页，避免硬切/闪黑
    @State private var outgoingImage: UIImage?
    @State private var outgoingOpacity: Double = 1

    /// 阅读统计（单例，主线程访问）
    private var stats: ReadingStatsStore { ReadingStatsStore.shared }

    var body: some View {
        ZStack {
            settings.comicBackground.color.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if pagePaths.isEmpty {
                emptyView
            } else {
                mainContent

                if settings.comicDim > 0.005 {
                    Color.black
                        .opacity(settings.comicDim)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if chromeVisible {
                    chromeOverlay
                        .transition(.opacity)
                }
            }
        }
        .task { await load() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.comicKeepAwake }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            hideItem?.cancel()
            saveProgress()
            stats.endSession()
        }
        .onChange(of: settings.comicAutoTrim) { _, _ in
            if settings.comicMode == .paged { Task { await showPage(pageIndex) } }
        }
        .onChange(of: settings.comicMode) { _, newValue in
            if newValue == .continuous {
                visibleIndex = pageIndex
                hideChrome()
            } else {
                pageIndex = visibleIndex
                Task { await showPage(pageIndex) }
            }
        }
        .onChange(of: settings.comicChrome) { _, newValue in
            if newValue == .always {
                withAnimation { chromeVisible = true }
            }
        }
        .sheet(isPresented: $showGrid) { gridSheet }
        .sheet(isPresented: $showSettings) { ComicSettingsView(settings: settings) }
    }

    // MARK: - 内容

    private var mainContent: some View {
        Group {
            if settings.comicMode == .paged {
                pagedContent
            } else {
                GeometryReader { geo in
                    continuousContent(width: geo.size.width)
                }
            }
        }
    }

    private var pagedContent: some View {
        ZStack {
            ComicPageView(
                image: image,
                fitMode: settings.comicFit,
                doubleTapZoom: settings.comicDoubleTapZoom,
                onSingleTap: { ratio in handleTap(ratio: ratio) },
                onSwipeLeft: { turnTowardNext() },
                onSwipeRight: { turnTowardPrev() },
                onZoomChanged: { zoomed = $0 },
                onEdgeExit: { exitReader() }
            )
            .ignoresSafeArea()

            if let outgoingImage {
                ComicStillPage(image: outgoingImage, fitMode: settings.comicFit)
                    .opacity(outgoingOpacity)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            if imageLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
            }
        }
    }

    private func continuousContent(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pagePaths.enumerated()), id: \.offset) { index, path in
                        ContinuousComicPage(
                            path: path,
                            url: book.absoluteURL,
                            width: width,
                            trim: settings.comicAutoTrim,
                            background: settings.comicBackground.color
                        )
                        .id(index)
                        .onAppear {
                            if index != visibleIndex {
                                visibleIndex = index
                                stats.noteActivity(pages: 1)
                                shelf.updateProgress(bookID: book.id, location: index, totalUnits: pagePaths.count)
                            }
                        }
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    scrollTarget = pageIndex
                }
            }
            .onChange(of: scrollTarget) { _, newValue in
                guard let target = newValue else { return }
                proxy.scrollTo(target, anchor: .top)
                scrollTarget = nil
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard width > 1 else { return }
                    handleTap(ratio: value.location.x / width)
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    if value.startLocation.x < 24, value.translation.width > 60 {
                        exitReader()
                    }
                }
            )
        }
    }

    private var loadingView: some View {
        ProgressView("正在读取漫画…")
            .tint(.white)
            .foregroundStyle(.white)
    }

    private var emptyView: some View {
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
    }

    // MARK: - 工具栏

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            topCapsule
                .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
                .padding(.top, ReaderChromeMetrics.topGap)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                bottomCapsule

                if settings.comicShowProgress {
                    progressLine
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
            .padding(.bottom, ReaderChromeMetrics.bottomGap)
        }
    }

    private var topCapsule: some View {
        ReaderCapsule(dark: true) {
            HStack(spacing: 4) {
                ChromeIconButton(systemName: "chevron.left", tint: .white) {
                    exitReader()
                }

                Text(book.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(pageText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.60))
                    .frame(minWidth: 56, alignment: .trailing)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 6)
        }
    }

    private var bottomCapsule: some View {
        ReaderCapsule(dark: true) {
            HStack(spacing: 0) {
                ChromeIconButton(systemName: "square.grid.2x2", tint: .white) {
                    showGrid = true
                }

                Spacer(minLength: 0)

                if settings.comicMode == .paged {
                    ChromeIconButton(systemName: "chevron.left", tint: .white) {
                        turnTowardPrev()
                    }
                    if settings.comicShowPageNumber {
                        Text(pageText)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(minWidth: 56)
                    }
                    ChromeIconButton(systemName: "chevron.right", tint: .white) {
                        turnTowardNext()
                    }
                } else if settings.comicShowPageNumber {
                    Text(pageText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 56)
                }

                Spacer(minLength: 0)

                ChromeIconButton(systemName: "gearshape", tint: .white) {
                    showSettings = true
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(Color.white.opacity(0.70))
                    .frame(width: max(2, geo.size.width * progressFraction))
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
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
                                isCurrent: index == currentPage
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showGrid = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showSettings = true }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showGrid = false }
                }
            }
        }
    }

    // MARK: - 计算

    private var currentPage: Int {
        settings.comicMode == .continuous ? visibleIndex : pageIndex
    }

    private var pageText: String {
        guard pagePaths.isEmpty == false else { return "0 / 0" }
        return "\(min(currentPage + 1, pagePaths.count)) / \(pagePaths.count)"
    }

    private var progressFraction: CGFloat {
        guard pagePaths.count > 1 else { return pagePaths.isEmpty ? 0 : 1 }
        return CGFloat(min(max(currentPage, 0), pagePaths.count - 1)) / CGFloat(pagePaths.count - 1)
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
        let start = min(max(0, book.location), max(0, paths.count - 1))
        pageIndex = start
        visibleIndex = start
        isLoading = false

        guard paths.isEmpty == false else { return }

        await showPage(start)
        shelf.updateProgress(bookID: book.id, location: start, totalUnits: paths.count)
        stats.beginSession(bookID: book.id)

        if settings.comicChrome == .always {
            withAnimation { chromeVisible = true }
        } else {
            showChromeTemporarily()
        }
    }

    @MainActor
    private func showPage(_ index: Int) async {
        guard pagePaths.indices.contains(index) else { return }
        let path = pagePaths[index]
        let url = book.absoluteURL
        let trim = settings.comicAutoTrim

        if let hit = ComicLoader.cachedImage(at: path, in: url, trim: trim) {
            setPageImage(hit)
            imageLoading = false
        } else {
            imageLoading = true
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                ComicLoader.image(at: path, in: url, trim: trim)
            }.value
            if pageIndex == index {
                setPageImage(loaded)
                imageLoading = false
            }
        }
        preload(around: index)
    }

    /// 换页：旧页留在上层淡出，新页立刻在下面就位，形成交叉溶解
    @MainActor
    private func setPageImage(_ newImage: UIImage?) {
        guard let newImage else {
            image = nil
            return
        }
        guard let old = image, old !== newImage else {
            image = newImage
            return
        }
        outgoingImage = old
        outgoingOpacity = 1
        image = newImage
        withAnimation(.easeOut(duration: 0.22)) { outgoingOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if outgoingOpacity < 0.02 { outgoingImage = nil }
        }
    }

    private func preload(around index: Int) {
        let depth = max(0, settings.comicPreload)
        guard depth > 0 else { return }
        let url = book.absoluteURL
        let trim = settings.comicAutoTrim
        for offset in 1...depth {
            for target in [index + offset, index - offset] where pagePaths.indices.contains(target) {
                let path = pagePaths[target]
                if ComicLoader.cachedImage(at: path, in: url, trim: trim) != nil { continue }
                Task.detached(priority: .utility) { _ = ComicLoader.image(at: path, in: url, trim: trim) }
            }
        }
    }

    private func jump(to index: Int) {
        guard pagePaths.indices.contains(index) else { return }
        pageIndex = index
        visibleIndex = index
        saveProgress()
        if settings.comicMode == .paged {
            Task { await showPage(index) }
        } else {
            scrollTarget = index
        }
    }

    private func turnTowardNext() {
        turn(by: settings.comicDirection == .rightToLeft ? -1 : 1)
    }

    private func turnTowardPrev() {
        turn(by: settings.comicDirection == .rightToLeft ? 1 : -1)
    }

    private func turn(by delta: Int) {
        guard settings.comicMode == .paged else { return }
        let target = pageIndex + delta
        guard pagePaths.indices.contains(target) else {
            // 到首/末页给一下硬一点的触感，避免误以为卡了
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pageIndex = target
        zoomed = false
        stats.noteActivity(pages: 1)
        saveProgress()
        Task { await showPage(target) }
    }

    private func handleTap(ratio: CGFloat) {
        stats.noteActivity()
        if zoomed { return }

        // 竖向滚动模式下点按只控制工具栏
        if settings.comicMode == .continuous {
            if chromeVisible, settings.comicChrome != .always {
                hideChrome()
            } else {
                toggleChrome()
            }
            return
        }

        // 工具栏开着时，点画面先收起（常驻模式除外）
        if chromeVisible, settings.comicChrome != .always {
            hideChrome()
            return
        }

        switch settings.comicTapZone {
        case .off:
            toggleChrome()
        case .two:
            if ratio < 0.42 {
                turnTowardPrev()
            } else if ratio > 0.58 {
                turnTowardNext()
            } else {
                toggleChrome()
            }
        case .three:
            if ratio < 0.33 {
                turnTowardPrev()
            } else if ratio > 0.67 {
                turnTowardNext()
            } else {
                toggleChrome()
            }
        }
    }

    private func toggleChrome() {
        switch settings.comicChrome {
        case .always:
            break
        case .autoHide:
            showChromeTemporarily()
        case .manual:
            hideItem?.cancel()
            withAnimation(.easeInOut(duration: 0.18)) { chromeVisible.toggle() }
        }
    }

    private func showChromeTemporarily() {
        hideItem?.cancel()
        withAnimation(.easeInOut(duration: 0.16)) { chromeVisible = true }
        guard settings.comicChrome == .autoHide else { return }
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
        }
        hideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.comicAutoHideDelay, execute: item)
    }

    private func hideChrome() {
        hideItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
    }

    private func exitReader() {
        hideItem?.cancel()
        saveProgress()
        onExit()
    }

    private func saveProgress() {
        guard pagePaths.isEmpty == false else { return }
        shelf.updateProgress(bookID: book.id, location: currentPage, totalUnits: pagePaths.count)
    }
}

// MARK: - 翻页过渡用的静态页

/// 和 ComicZoomView 采用同一套尺寸规则（整页/铺满宽/铺满高 + 居中），
/// 保证淡出过程中新旧两页对得上，不会跳动。
struct ComicStillPage: View {
    let image: UIImage
    let fitMode: ComicFitMode

    var body: some View {
        GeometryReader { geo in
            let iw = max(image.size.width, 1)
            let ih = max(image.size.height, 1)
            let wScale = geo.size.width / iw
            let hScale = geo.size.height / ih
            let scale: CGFloat = {
                switch fitMode {
                case .screen: return min(wScale, hScale)
                case .width: return wScale
                case .height: return hScale
                }
            }()

            Image(uiImage: image)
                .resizable()
                .frame(width: iw * scale, height: ih * scale)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .clipped()
    }
}

// MARK: - 连续滚动单页

struct ContinuousComicPage: View {
    let path: String
    let url: URL
    let width: CGFloat
    let trim: Bool
    let background: Color

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
            } else {
                Rectangle()
                    .fill(background)
                    .frame(width: width, height: width * 1.4)
                    .overlay {
                        if failed {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.gray)
                        } else {
                            ProgressView().tint(.gray)
                        }
                    }
            }
        }
        .task {
            guard image == nil else { return }
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                ComicLoader.image(at: path, in: url, trim: trim)
            }.value
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
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
