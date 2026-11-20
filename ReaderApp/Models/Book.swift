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

        // v1.8.2：有扩展名但不是支持格式 → 直接判「不是书」，不再猜内容。
        // 以前这里会继续嗅探，结果书源文件 sources.json / bookmarks.json 被当成 TXT
        // 收进书架（还被改名成 .txt 搬进 Books/），书源文件因此消失。
        if url.pathExtension.isEmpty == false { return nil }

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

        // 纯文本启发：只看开头一小段，绝不把整个文件读进内存。
        // 以前这里 Data(contentsOf: url) 会把几百 MB 的 TXT 整个读进来，
        // 大点的合集直接触发内存告警被系统杀掉，表现就是「导入不了 / 闪退」。
        let sample = (try? handle.read(upToCount: 8192)) ?? Data()
        guard sample.isEmpty == false else { return nil }
        if sample.contains(0) { return nil }

        // 控制字符太多基本是二进制（图片 / 压缩包），别硬当文本
        let binaryCount = sample.filter { byte in
            byte < 0x09 || (byte > 0x0D && byte < 0x20)
        }.count
        let binaryRatio = Double(binaryCount) / Double(sample.count)
        if binaryRatio > 0.30 { return nil }

        if TextLoader.decode(sample, allowPartial: true) != nil { return .txt }
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

    // MARK: - 来源与更新检测（从书源下载的书才有，本地导入为 nil）
    var sourceID: UUID?
    var sourceLink: String?
    var sourceName: String?
    /// 下载时的章节数
    var downloadedChapterCount: Int?
    /// 下载时的最新章节名
    var latestChapter: String?
    var checkedAt: Date?
    /// 检测到有新章节
    var hasUpdate: Bool = false

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

    enum CodingKeys: String, CodingKey {
        case id, title, author, format, fileName, location, totalUnits, addedAt, lastReadAt
        case sourceID, sourceLink, sourceName, downloadedChapterCount, latestChapter, checkedAt, hasUpdate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名"
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "未知"
        format = try c.decodeIfPresent(BookFormat.self, forKey: .format) ?? .txt
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        location = try c.decodeIfPresent(Int.self, forKey: .location) ?? 0
        totalUnits = try c.decodeIfPresent(Int.self, forKey: .totalUnits) ?? 0
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastReadAt = try c.decodeIfPresent(Date.self, forKey: .lastReadAt)
        sourceID = try c.decodeIfPresent(UUID.self, forKey: .sourceID)
        sourceLink = try c.decodeIfPresent(String.self, forKey: .sourceLink)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        downloadedChapterCount = try c.decodeIfPresent(Int.self, forKey: .downloadedChapterCount)
        latestChapter = try c.decodeIfPresent(String.self, forKey: .latestChapter)
        checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt)
        hasUpdate = try c.decodeIfPresent(Bool.self, forKey: .hasUpdate) ?? false
    }
}
