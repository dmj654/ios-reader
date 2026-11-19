//
//  Book.swift
//  ReaderApp
//
//  书籍数据模型
//

import Foundation
import SwiftUI

/// 支持的书籍格式
enum BookFormat: String, Codable, Hashable, CaseIterable {
    case txt = "TXT"
    case epub = "EPUB"
    case pdf = "PDF"
    case comic = "CBZ"

    static func from(fileURL: URL) -> BookFormat? {
        switch fileURL.pathExtension.lowercased() {
        case "txt", "text": return .txt
        case "epub": return .epub
        case "pdf": return .pdf
        case "cbz", "zip": return .comic
        default: return nil
        }
    }

    var iconName: String {
        switch self {
        case .txt: return "text.alignleft"
        case .epub: return "book"
        case .pdf: return "doc.richtext"
        case .comic: return "photo.on.rectangle"
        }
    }

    var tintColor: Color {
        switch self {
        case .txt: return Color(red: 0.42, green: 0.33, blue: 0.24)
        case .epub: return Color(red: 0.20, green: 0.45, blue: 0.42)
        case .pdf: return Color(red: 0.35, green: 0.35, blue: 0.55)
        case .comic: return Color(red: 0.55, green: 0.30, blue: 0.35)
        }
    }
}

/// 一本书
struct Book: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var author: String = "未知"
    var format: BookFormat
    /// 沙盒 Documents/Books/ 下的文件名
    var fileName: String
    /// 阅读位置：TXT 为字符偏移，PDF/漫画为页索引
    var location: Int = 0
    /// 总单位数：TXT 为总字数，PDF/漫画为总页数
    var totalUnits: Int = 0
    var addedAt: Date = Date()
    var lastReadAt: Date?

    var absoluteURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Books").appendingPathComponent(fileName)
    }

    /// 0 ~ 1 的阅读进度
    var progress: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, max(0, Double(location) / Double(totalUnits)))
    }

    var isRead: Bool { totalUnits > 0 && location >= totalUnits - 1 }
}
