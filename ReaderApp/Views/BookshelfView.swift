//
//  BookshelfView.swift
//  ReaderApp
//
//  书架首页
//

import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject var shelf: BookshelfViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = ReadingSettings()
    @State private var showImporter = false
    @State private var selectedBook: Book?
    @State private var showSettings = false
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 18)]

    var body: some View {
        NavigationStack {
            ZStack {
                if shelf.books.isEmpty {
                    emptyState
                } else {
                    grid
                }
                if let toast {
                    toastView(toast)
                }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shelf.scan()
                        show("已刷新书架")
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls { shelf.importBook(from: url) }
                    if let msg = shelf.alertMessage {
                        shelf.alertMessage = nil
                        show("导入失败：\(msg)")
                    } else {
                        show("已导入 \(urls.count) 个文件")
                    }
                case .failure(let error):
                    show("选择文件失败：\(error.localizedDescription)")
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
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
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

    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        types.append(.item)          // 兜底：允许所有文件
        types.append(.plainText)
        types.append(.pdf)
        types.append(.zip)
        for ext in ["epub", "cbz", "txt", "azw3", "mobi"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    // MARK: - 书架网格

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(shelf.books) { book in
                    Button { selectedBook = book } label: {
                        BookCell(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            selectedBook = book
                        } label: {
                            Label("继续阅读", systemImage: "book")
                        }
                        Button(role: .destructive) {
                            shelf.delete(book)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .refreshable { shelf.scan() }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
                Text("书架是空的")
                    .font(.title3.weight(.medium))
                Text("支持 TXT / EPUB / PDF / CBZ 漫画")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("点右上角 +，从「文件」里选书", systemImage: "plus.circle")
                    Label("或把书放进「文件」App → 我的 iPhone → 本地阅读器", systemImage: "folder")
                    Label("放好之后点右上角刷新按钮，或把这个 App 切到后台再回来", systemImage: "arrow.clockwise")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 8)
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
}

// MARK: - 单本书的卡片

struct BookCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [book.format.tintColor.opacity(0.85), book.format.tintColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: book.format.iconName)
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(book.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .padding(.horizontal, 10)
                        }
                        .padding(10)
                    )

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule()
                            .fill(.white)
                            .frame(width: max(2, geo.size.width * book.progress))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Text(book.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(book.format.rawValue)
                if book.progress > 0.01 {
                    Text("·")
                    Text("\(Int(book.progress * 100))%")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }
}
