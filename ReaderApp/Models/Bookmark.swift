//
//  Bookmark.swift
//  ReaderApp
//
//  书签：按书 + 字符偏移存，跨分页/跨字号都稳定
//

import Foundation

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    /// 全文 UTF-16 偏移
    var offset: Int
    /// 所在章节名
    var chapter: String
    /// 正文摘要
    var snippet: String
    var createdAt: Date = Date()
}
