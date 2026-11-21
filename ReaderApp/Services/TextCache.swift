//
//  TextCache.swift
//  ReaderApp
//
//  解析结果缓存：TXT / EPUB 第一次解析后把「章节列表」存成 JSON，
//  下次打开直接读缓存，不再解压 EPUB、不再整本解码 TXT。
//  用文件大小 + 修改时间做指纹，书被替换后自动失效。
//

import Foundation

enum TextCache {

    private struct Payload: Codable {
        var signature: String
        var title: String
        var author: String
        var chapters: [Chapter]
    }

    /// 缓存目录放在 Application Support（用户看不到，也不会被「文件」App 误改）
    private static var defaultDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TextCache", isDirectory: true)
    }

    static func fileURL(bookID: UUID, dir: URL? = nil) -> URL {
        (dir ?? defaultDir).appendingPathComponent(bookID.uuidString).appendingPathExtension("json")
    }

    /// 文件指纹：大小 + 修改时间
    static func signature(for source: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int(mtime))"
    }

    static func load(bookID: UUID, source: URL, dir: URL? = nil) -> BookText? {
        let file = fileURL(bookID: bookID, dir: dir)
        guard let data = try? Data(contentsOf: file),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        // 指纹不一致说明书换了，缓存作废
        guard payload.signature == signature(for: source) else { return nil }
        guard payload.chapters.isEmpty == false else { return nil }
        return BookText(title: payload.title, author: payload.author, chapters: payload.chapters)
    }

    static func save(_ text: BookText, bookID: UUID, source: URL, dir: URL? = nil) {
        guard text.chapters.isEmpty == false else { return }
        let fm = FileManager.default
        let targetDir = dir ?? defaultDir
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let payload = Payload(
            signature: signature(for: source),
            title: text.title,
            author: text.author,
            chapters: text.chapters
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL(bookID: bookID, dir: dir), options: .atomic)
    }

    static func remove(bookID: UUID, dir: URL? = nil) {
        try? FileManager.default.removeItem(at: fileURL(bookID: bookID, dir: dir))
    }

    /// 书籍被删除时一并清掉插图目录
    static func removeImages(bookID: UUID) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("BookImages", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
