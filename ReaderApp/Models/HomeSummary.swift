//
//  HomeSummary.swift
//  ReaderApp
//
//  主页卡片摘要的纯逻辑：最近在读、最近导入封面、历史记录数、可用书源数。
//  不依赖 SwiftUI 视图，方便单元测试直接覆盖。
//

import Foundation

enum HomeSummary {

    /// 最近在读：lastReadAt 最新；缺失回退 addedAt
    static func mostRecentBook(books: [Book]) -> Book? {
        books.sorted {
            ($0.lastReadAt ?? Date.distantPast) > ($1.lastReadAt ?? Date.distantPast)
        }.first
    }

    /// 最近导入的封面（按 addedAt 倒序，最多 limit 张）
    static func recentCovers(books: [Book], limit: Int = 4) -> [Book] {
        books.sorted { $0.addedAt > $1.addedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 历史记录数：统计里有、且书架仍在的书
    static func historyCount(books: [Book], stats: [String: BookStat]) -> Int {
        let ids = Set(books.map { $0.id.uuidString })
        return stats.keys.filter { ids.contains($0) }.count
    }

    /// 可用书源数：启用且规则可在本机跑（不依赖宿主绑定）
    static func usableSourceCount(sources: [BookSource]) -> Int {
        sources.filter { $0.enabled && $0.searchUnsupportedReason == nil }.count
    }
}
