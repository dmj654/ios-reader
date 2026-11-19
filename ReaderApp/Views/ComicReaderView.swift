//
//  ComicReaderView.swift
//  ReaderApp
//
//  漫画阅读：压缩包内图片逐页显示，支持双指缩放
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
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("正在读取漫画…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if pagePaths.isEmpty {
                Text("这本书里没有找到图片，可能是压缩格式不支持。")
                    .foregroundStyle(.white)
                    .padding(40)
                    .multilineTextAlignment(.center)
            } else {
                GeometryReader { geo in
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(zoom)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            zoom = min(4, max(1, lastZoom * value))
                                        }
                                        .onEnded { _ in
                                            lastZoom = zoom
                                            if zoom < 1.05 {
                                                withAnimation { zoom = 1; lastZoom = 1 }
                                            }
                                        }
                                )
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        // 先还原缩放，再判定翻页
                        if zoom > 1.02 { withAnimation { zoom = 1; lastZoom = 1 }; return }
                        if location.x < geo.size.width * 0.3 {
                            turn(by: -1)
                        } else if location.x > geo.size.width * 0.7 {
                            turn(by: 1)
                        } else {
                            withAnimation { showMenu.toggle() }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 40)
                            .onEnded { value in
                                guard zoom < 1.05 else { return }
                                if value.translation.width < -50 {
                                    turn(by: 1)
                                } else if value.translation.width > 50 {
                                    turn(by: -1)
                                }
                            }
                    )
                }
                .ignoresSafeArea()
            }

            if showMenu, pagePaths.isEmpty == false {
                menuOverlay
                    .transition(.opacity)
            }
        }
        .task { await load() }
        .onDisappear { saveProgress() }
    }

    private var menuOverlay: some View {
        VStack {
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
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.black.opacity(0.6))

            Spacer()

            HStack(spacing: 12) {
                Text("\(pageIndex + 1)")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(pageIndex) },
                        set: { newValue in
                            pageIndex = min(pagePaths.count - 1, max(0, Int(newValue)))
                            resetZoom()
                            saveProgress()
                        }
                    ),
                    in: 0...Double(max(1, pagePaths.count - 1))
                )
                Text("\(pagePaths.count)")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 34)
            .background(.black.opacity(0.6))
        }
        .foregroundStyle(.white)
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
            await loadImage(at: pageIndex)
            shelf.updateProgress(bookID: book.id, location: pageIndex, totalUnits: paths.count)
        }
    }

    @MainActor
    private func loadImage(at index: Int) async {
        guard index >= 0, index < pagePaths.count else { return }
        let path = pagePaths[index]
        let url = book.absoluteURL
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            ComicLoader.image(at: path, in: url)
        }.value
        if pagePaths.indices.contains(index), pageIndex == index {
            image = loaded
        }
    }

    private func turn(by delta: Int) {
        let target = pageIndex + delta
        guard target >= 0, target < pagePaths.count else { return }
        pageIndex = target
        resetZoom()
        saveProgress()
        Task { await loadImage(at: target) }
    }

    private func resetZoom() {
        zoom = 1
        lastZoom = 1
    }

    private func saveProgress() {
        shelf.updateProgress(bookID: book.id, location: pageIndex, totalUnits: pagePaths.count)
    }
}
