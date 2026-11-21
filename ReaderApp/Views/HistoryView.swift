//
//  HistoryView.swift
//  ReaderApp
//
//  历史列表：读过的本地书按最近阅读时间倒序；点进去继续读，左滑清除单条记录。
//  第一版只关联本地书，不接在线书历史。
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject private var stats = ReadingStatsStore.shared

    var onOpenBook: (Book) -> Void

    @Environment(\.dismiss) private var dismiss

    private var entries: [HistoryEntry] {
        HistoryModel.entries(books: shelf.books, stats: stats.books)
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        row(entry)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpenBook(entry.book)
                            }
                    }
                    .onDelete { offsets in
                        offsets.map { entries[$0].id }.forEach { stats.clearBook(id: $0) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text("还没有阅读记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("导入或在线读一本书后，会出现在这里")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            HistoryCover(book: entry.book)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.book.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                Text(authorText(entry.book))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(1)
                Text("\(StatsFormat.day(entry.stat.lastAt)) · \(StatsFormat.duration(entry.stat.seconds)) · \(entry.stat.pages) 页")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appCard(radius: AppTheme.radiusInner)
    }

    private func authorText(_ book: Book) -> String {
        if let source = book.sourceName, source.isEmpty == false {
            return "\(book.author) · \(source)"
        }
        return book.author
    }
}

// MARK: - 历史条目封面

private struct HistoryCover: View {
    let book: Book

    @State private var cover: UIImage?

    var body: some View {
        ZStack {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [book.format.tintColor.opacity(0.92), book.format.tintColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Text(initial)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 0.5)
        )
        .task { loadCover() }
    }

    private var initial: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).isEmpty ? "书" : String(trimmed.prefix(1))
    }

    private func loadCover() {
        if let disk = CoverStore.cached(bookID: book.id) {
            cover = disk
            return
        }
        guard book.format != .txt else { return }
        Task.detached(priority: .utility) {
            let image = CoverStore.generate(url: book.absoluteURL, format: book.format, bookID: book.id)
            await MainActor.run { cover = image }
        }
    }
}
