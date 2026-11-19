//
//  PdfReaderView.swift
//  ReaderApp
//
//  PDF 阅读：PDFKit 单页显示 + 手势翻页 + 进度记忆
//

import SwiftUI
import PDFKit

struct PdfReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    let onExit: () -> Void

    @EnvironmentObject var shelf: BookshelfViewModel

    @State private var document: PDFDocument?
    @State private var pageIndex: Int = 0
    @State private var showMenu = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let document {
                PdfPageView(document: document, pageIndex: pageIndex)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showMenu.toggle() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 30, coordinateSpace: .global)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                guard abs(dx) > abs(dy) else { return }
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
                    )
            } else {
                ProgressView("正在打开 PDF…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .task { load() }
            }

            if showMenu, let document {
                menuOverlay(total: document.pageCount)
                    .transition(.opacity)
            }
        }
        .onDisappear { saveProgress() }
    }

    private func menuOverlay(total: Int) -> some View {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background { Color.black.opacity(0.7).ignoresSafeArea(edges: .top) }

            Spacer()

            HStack(spacing: 12) {
                Text("\(pageIndex + 1)")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(pageIndex) },
                        set: { newValue in
                            pageIndex = min(total - 1, max(0, Int(newValue)))
                            saveProgress()
                        }
                    ),
                    in: 0...Double(max(1, total - 1))
                )
                Text("\(total)")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background { Color.black.opacity(0.7).ignoresSafeArea(edges: .bottom) }
        }
        .foregroundStyle(.white)
    }

    @MainActor
    private func load() {
        guard document == nil else { return }
        let doc = PDFDocument(url: book.absoluteURL)
        document = doc
        pageIndex = min(max(0, book.location), max(0, (doc?.pageCount ?? 1) - 1))
    }

    private func turn(by delta: Int) {
        guard let document else { return }
        let target = pageIndex + delta
        guard target >= 0, target < document.pageCount else { return }
        pageIndex = target
        saveProgress()
    }

    private func saveProgress() {
        guard let document else { return }
        shelf.updateProgress(bookID: book.id, location: pageIndex, totalUnits: document.pageCount)
    }
}

// MARK: - PDFKit 单页视图

struct PdfPageView: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.isUserInteractionEnabled = false
        view.pageShadowsEnabled = false
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        if let page = document.page(at: pageIndex) {
            view.go(to: page)
        }
    }
}
