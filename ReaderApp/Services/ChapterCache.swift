//
//  ChapterCache.swift
//  ReaderApp
//
//  在线阅读的章节离线缓存：一章一个 txt，按书籍链接分目录。
//  读过的自动存，也可以整本缓存；重启后接着用，不重复下。
//

import Foundation

enum ChapterCache {

    struct Meta: Codable {
        var name: String
        var link: String
        var sourceName: String
        var chapterCount: Int
        var updatedAt: Date
    }

    /// 缓存的根目录
    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ChapterCache", isDirectory: true)
    }

    /// 用书链接算一个稳定目录名（跨启动不变）
    static func key(_ link: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in link.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func folder(for link: String) -> URL {
        root.appendingPathComponent(key(link), isDirectory: true)
    }

    private static func file(for link: String, index: Int) -> URL {
        folder(for: link).appendingPathComponent("\(index).txt")
    }

    // MARK: - 读

    static func text(link: String, index: Int) -> String? {
        let url = file(for: link, index: index)
        guard let data = try? Data(contentsOf: url), data.isEmpty == false else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func meta(for link: String) -> Meta? {
        let url = folder(for: link).appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    /// 已缓存的章号（0 起）
    static func cachedIndices(link: String) -> Set<Int> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(for: link).path)) ?? []
        var result = Set<Int>()
        for name in names where name.hasSuffix(".txt") {
            if let index = Int(name.dropLast(4)) {
                result.insert(index)
            }
        }
        return result
    }

    static func cachedCount(link: String) -> Int {
        cachedIndices(link: link).count
    }

    /// 缓存占用的空间（字节）
    static func totalBytes() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }

    // MARK: - 写

    @discardableResult
    static func store(link: String, index: Int, text: String, meta: Meta? = nil) -> Bool {
        let dir = folder(for: link)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = text.data(using: .utf8) {
            try? data.write(to: file(for: link, index: index), options: .atomic)
        } else {
            return false
        }

        if let meta {
            let url = dir.appendingPathComponent("meta.json")
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return true
    }

    static func clear(link: String) {
        try? FileManager.default.removeItem(at: folder(for: link))
    }

    /// 只写元信息（书名、源名、章数），不占章节文件
    static func saveMeta(_ meta: Meta) {
        let dir = folder(for: meta.link)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
    }
}

// MARK: - 整本缓存的进度

@MainActor
final class OfflineCacheStore: ObservableObject {
    static let shared = OfflineCacheStore()

    @Published private(set) var busyLink: String?
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var statusText = ""
    @Published private(set) var finishedMessage: String?

    private var cancelled = false

    var progress: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    func isRunning(link: String) -> Bool {
        busyLink == link
    }

    func cancel() {
        cancelled = true
    }

    /// 整本缓存：已缓存过的章直接跳过，等于断点续传
    func cache(source: BookSource, item: SourceItem, chapters: [SourceChapter], limit: Int) async {
        guard busyLink == nil else { return }
        guard chapters.isEmpty == false else { return }

        let list = limit > 0 ? Array(chapters.prefix(limit)) : chapters
        let link = item.link
        let cached = ChapterCache.cachedIndices(link: link)

        cancelled = false
        busyLink = link
        total = list.count
        done = cached.filter { $0 < list.count }.count
        statusText = "已缓存 \(done)/\(list.count) 章"
        finishedMessage = nil

        let meta = ChapterCache.Meta(
            name: item.name,
            link: link,
            sourceName: source.name,
            chapterCount: chapters.count,
            updatedAt: Date()
        )
        // 先把元信息落下来，重启后能认出这是哪本书
        ChapterCache.saveMeta(meta)

        var failed = 0

        for index in list.indices {
            if cancelled { break }
            if cached.contains(index) { continue }

            do {
                let body = try await SourceClient.chapterText(source: source, chapter: list[index])
                if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    ChapterCache.store(link: link, index: index, text: body)
                    done += 1
                } else {
                    failed += 1
                }
            } catch {
                failed += 1
            }

            statusText = "已缓存 \(done)/\(list.count) 章" + (failed > 0 ? "，失败 \(failed)" : "")
        }

        busyLink = nil
        let wasCancelled = cancelled
        cancelled = false

        if wasCancelled {
            finishedMessage = "已停止，缓存了 \(done)/\(list.count) 章，再点一次会接着下"
        } else if failed > 0 {
            finishedMessage = "缓存完成 \(done)/\(list.count) 章，\(failed) 章没取到（源的问题），可以再点一次补下"
        } else {
            finishedMessage = "整本缓存好了，断网也能读"
        }
    }
}
