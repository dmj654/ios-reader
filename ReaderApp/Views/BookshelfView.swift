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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
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
                    if let msg = shelf.message {
                        show(msg)
                        shelf.message = nil
                    }
                case .failure(let error):
                    show("选择文件失败：\(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .navigationDestination(item: $selectedBook) { book in
                ReaderView(book: book, settings: settings)
            }
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf, .zip]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        types.append(.data)
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
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("书架是空的")
                .font(.title3.weight(.medium))
            Text("点右上角 + 从「文件」导入\n支持 TXT / EPUB / PDF / CBZ 漫画")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
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

                // 底部进度条
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
