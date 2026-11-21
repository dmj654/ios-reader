//
//  HistoryModel.swift
//  ReaderApp
//
//  历史记录匹配：统计里有、且书架仍在的书，按最近阅读时间倒序。
//

import Foundation

struct HistoryEntry: Identifiable {
    let id: UUID
    let book: Book
    let stat: BookStat
}

enum HistoryModel {

    /// 书架书目与阅读统计按 UUID 关联；孤立统计（书已删）不展示
    static func entries(books: [Book], stats: [String: BookStat]) -> [HistoryEntry] {
        books.compactMap { book -> HistoryEntry? in
            guard let stat = stats[book.id.uuidString] else { return nil }
            return HistoryEntry(id: book.id, book: book, stat: stat)
        }
        .sorted { $0.stat.lastAt > $1.stat.lastAt }
    }
}
