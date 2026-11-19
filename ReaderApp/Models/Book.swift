//
//  Book.swift
//  ReaderApp
//
//  书籍数据模型
//

import Foundation
import SwiftUI
import ZIPFoundation

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

    /// 对应扩展名（用于给没有扩展名的文件补上）
    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .epub: return "epub"
        case .pdf: return "pdf"
        case .comic: return "cbz"
        }
    }

    /// 先看扩展名，认不出来就嗅探文件头。
    /// 微信 / QQ 存下来的书经常没有扩展名（文件名就是 "1"、"31" 这种），必须靠内容判断。
    static func detect(for url: URL) -> BookFormat? {
        if let f = from(fileURL: url) { return f }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8)) ?? Data()

        if head.starts(with: Array("%PDF".utf8)) { return .pdf }

        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            // ZIP 家族：有 META-INF/container.xml 就是 EPUB，否则当漫画包
            if let archive = Archive(url: url, accessMode: .read),
               archive["META-INF/container.xml"] != nil {
                return .epub
            }
            return .comic
        }

        // 纯文本启发：无 NUL 字节且能被文本解码器读出来
        if let data = try? Data(contentsOf: url), data.isEmpty == false {
            let sample = data.prefix(4096)
            if sample.contains(0) == false, TextLoader.decode(data) != nil {
                return .txt
            }
        }
        return nil
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
