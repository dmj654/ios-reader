//
//  SourceViewModel.swift
//  ReaderApp
//
//  书源相关状态：搜索、取目录、整本下载成 TXT / CBZ 并入书架
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class SourceViewModel: ObservableObject {

    // 搜索
    @Published var keyword = ""
    @Published var results: [SourceItem] = []
    @Published var searching = false
    @Published var errorMessage: String?
    /// 每个源各自的失败原因，成功时也保留，方便排查（只留前几条明细，避免一千条刷屏）
    @Published var failures: [String] = []
    /// 进度：已搜完 N 个 / 计划搜 M 个
    @Published var searchedCount = 0
    @Published var plannedCount = 0
    /// 失败原因归并后的统计，一千条源看这个就够
    @Published var failureBuckets: [FailureBucket] = []

    struct FailureBucket: Identifiable, Hashable {
        let id = UUID()
        var reason: String
        var count: Int
        var sample: String
    }

    private var cancelRequested = false

    // 目录
    @Published var chapters: [SourceChapter] = []
    @Published var meta = BookMeta()
    @Published var chaptersLoading = false
    @Published var chapterError: String?

    // 下载
    @Published var downloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var failedCount = 0
    @Published var finishedMessage: String?

    // MARK: - 搜索

    func cancelSearch() {
        cancelRequested = true
    }

    /// 一次最多搜 limit 个源，每批只并发 batchSize 个。
    /// 一千条源同时发请求会把连接池和内存打满，全部超时 → 一本都搜不到。
    func search(sources: [BookSource], limit: Int = 30, store: SourceStore? = nil) async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        guard sources.isEmpty == false else {
            errorMessage = "这个分类下没有可用的书源。先到「书源管理」新建或导入，并打开开关。"
            return
        }

        cancelRequested = false
        searching = true
        errorMessage = nil
        results = []
        failures = []
        failureBuckets = []
        searchedCount = 0

        // 一千条里先把「以前搜成功过、最近没失败」的挑出来
        let queue = Array(prioritized(sources).prefix(max(1, limit)))
        plannedCount = queue.count

        let batchSize = 6
        var seenLinks = Set<String>()
        var errors: [String] = []
        var buckets: [String: (count: Int, sample: String)] = [:]
        var outcomes: [UUID: Bool] = [:]

        var start = 0
        while start < queue.count {
            if cancelRequested { break }
            let end = min(start + batchSize, queue.count)
            let slice = Array(queue[start..<end])

            let batch = await withTaskGroup(of: (BookSource, Result<[SourceItem], SourceFailure>).self) {
                group -> [(BookSource, Result<[SourceItem], SourceFailure>)] in
                for source in slice {
                    group.addTask {
                        do {
                            return (source, .success(try await SourceClient.search(source: source, keyword: text)))
                        } catch let failure as SourceFailure {
                            return (source, .failure(failure))
                        } catch {
                            return (source, .failure(SourceFailure(message: error.localizedDescription)))
                        }
                    }
                }
                var collected: [(BookSource, Result<[SourceItem], SourceFailure>)] = []
                for await item in group { collected.append(item) }
                return collected
            }

            if cancelRequested { break }

            for (source, result) in batch {
                switch result {
                case .success(let items):
                    outcomes[source.id] = true
                    for item in items where seenLinks.contains(item.link) == false {
                        seenLinks.insert(item.link)
                        results.append(item)
                    }
                case .failure(let failure):
                    outcomes[source.id] = false
                    errors.append("「\(source.name)」\(failure.message)")
                    let key = Self.failureKey(failure.message)
                    let existing = buckets[key]
                    buckets[key] = (count: (existing?.count ?? 0) + 1,
                                    sample: existing?.sample ?? source.name)
                }
            }

            start = end
            searchedCount = start
        }

        results.sort { lhs, rhs in
            let leftExact = lhs.name == text
            let rightExact = rhs.name == text
            if leftExact != rightExact { return leftExact }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        failures = Array(errors.prefix(6))
        failureBuckets = buckets
            .map { FailureBucket(reason: $0.key, count: $0.value.count, sample: $0.value.sample) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.reason < rhs.reason
            }

        // 结果统一登记一次，只写一次盘（一千条也不卡）
        store?.applySearchOutcomes(outcomes)

        searching = false

        if results.isEmpty {
            if cancelRequested {
                errorMessage = "已取消搜索"
            } else if errors.isEmpty {
                errorMessage = "所有源都没搜到这条，换个关键词试试"
            }
        }
    }

    /// 排序：搜成功过的 → 最近成功过的 → 失败少的 → 名字
    private func prioritized(_ sources: [BookSource]) -> [BookSource] {
        sources.sorted { lhs, rhs in
            if lhs.successCount != rhs.successCount { return lhs.successCount > rhs.successCount }
            let leftDate = lhs.lastSuccessAt ?? Date.distantPast
            let rightDate = rhs.lastSuccessAt ?? Date.distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            if lhs.failCount != rhs.failCount { return lhs.failCount < rhs.failCount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 把五花八门的报错压成人能看懂的几类
    static func failureKey(_ message: String) -> String {
        if message.contains("超时") || message.contains("timed out") || message.contains("The request timed out") {
            return "网络超时：站点连不上或被墙"
        }
        if message.contains("网络请求失败") || message.contains("离线") || message.contains("Internet") {
            return "网络请求失败：DNS / 连接被拦"
        }
        if message.contains("403") {
            return "403：站点要 Cookie / 换 UA / 防盗链"
        }
        if message.contains("404") {
            return "404：搜索地址失效"
        }
        if message.contains("5") && message.contains("服务器返回") {
            return "5xx：站点自己出错"
        }
        if message.contains("页面内容为空") {
            return "返回空页面：可能要登录或要验证码"
        }
        if message.contains("没有匹配") {
            return "规则对不上页面：站点改版或 list 规则写错"
        }
        if message.contains("提取不到书名") {
            return "取不到书名：name / link 规则写错"
        }
        if message.contains("地址不合法") {
            return "搜索地址不合法"
        }
        return message
    }

    // MARK: - 目录

    func loadChapters(source: BookSource, item: SourceItem) async {
        chaptersLoading = true
        chapterError = nil
        chapters = []
        meta = BookMeta()
        do {
            let detail = try await SourceClient.chapters(source: source, item: item)
            chapters = detail.chapters
            meta = detail.meta
        } catch let failure as SourceFailure {
            chapterError = failure.message
        } catch {
            chapterError = error.localizedDescription
        }
        chaptersLoading = false
    }

    // MARK: - 下载

    func download(source: BookSource, item: SourceItem, limit: Int, shelf: BookshelfViewModel) async -> Book? {
        guard downloading == false else { return nil }
        downloading = true
        progress = 0
        failedCount = 0
        finishedMessage = nil

        if chapters.isEmpty {
            await loadChapters(source: source, item: item)
        }
        guard chapters.isEmpty == false else {
            downloading = false
            finishedMessage = chapterError ?? "没有拿到章节"
            return nil
        }

        let list = limit > 0 ? Array(chapters.prefix(limit)) : chapters
        let book: Book?

        switch item.type {
        case .novel:
            book = await downloadNovel(source: source, item: item, list: list, shelf: shelf)
        case .comic:
            book = await downloadComic(source: source, item: item, list: list, shelf: shelf)
        }

        downloading = false
        return book
    }

    private func downloadNovel(source: BookSource, item: SourceItem, list: [SourceChapter],
                               shelf: BookshelfViewModel) async -> Book? {
        var buffer = item.name + "\n"
        if item.author.isEmpty == false { buffer += "作者：\(item.author)\n" }
        buffer += "\n"

        let batchSize = 4
        for start in stride(from: 0, to: list.count, by: batchSize) {
            let end = min(start + batchSize, list.count)
            let slice = Array(list[start..<end])

            let fetched = await withTaskGroup(of: (Int, String, String?).self) { group -> [(Int, String, String?)] in
                for offset in 0..<slice.count {
                    let chapter = slice[offset]
                    group.addTask {
                        let text = try? await SourceClient.chapterText(source: source, chapter: chapter)
                        return (start + offset, chapter.name, text)
                    }
                }
                var collected: [(Int, String, String?)] = []
                for await result in group { collected.append(result) }
                return collected.sorted { $0.0 < $1.0 }
            }

            for (_, chapterName, text) in fetched {
                if let text {
                    buffer += "\n\n" + chapterName + "\n\n" + text + "\n"
                } else {
                    failedCount += 1
                }
            }

            progress = Double(end) / Double(list.count)
            statusText = "已下载 \(end)/\(list.count) 章"
        }

        let name = Self.safeName(item.name)
        let dir = shelf.booksDir
        let dest = uniqueURL(name: name, ext: "txt", dir: dir)

        guard let data = buffer.data(using: .utf8), (try? data.write(to: dest, options: .atomic)) != nil else {
            finishedMessage = "写文件失败"
            return nil
        }

        shelf.scan()
        let saved = shelf.books.first { $0.fileName == dest.lastPathComponent }
        if let saved {
            shelf.attachProvenance(
                bookID: saved.id,
                sourceID: source.id,
                sourceLink: item.link,
                sourceName: source.name,
                chapterCount: list.count,
                latestChapter: list.last?.name ?? ""
            )
        }
        finishedMessage = failedCount > 0
            ? "已保存到书架（\(list.count - failedCount)/\(list.count) 章，\(failedCount) 章失败）"
            : "已保存到书架：\(list.count) 章"
        return saved
    }

    private func downloadComic(source: BookSource, item: SourceItem, list: [SourceChapter],
                               shelf: BookshelfViewModel) async -> Book? {
        var entries: [(name: String, data: Data)] = []
        var index = 0

        for (chapterIndex, chapter) in list.enumerated() {
            statusText = "第 \(chapterIndex + 1)/\(list.count) 章 · 正在取图"

            let images: [String]
            do {
                images = try await SourceClient.chapterImages(source: source, chapter: chapter)
            } catch {
                failedCount += 1
                progress = Double(chapterIndex + 1) / Double(list.count)
                continue
            }

            let targets = Array(images.prefix(200))
            let batchSize = 4
            for start in stride(from: 0, to: targets.count, by: batchSize) {
                let end = min(start + batchSize, targets.count)
                let slice = Array(targets[start..<end])

                let fetched = await withTaskGroup(of: (Int, Data?).self) { group -> [(Int, Data?)] in
                    for offset in 0..<slice.count {
                        let url = slice[offset]
                        let referer = chapter.link
                        group.addTask {
                            do {
                                let raw = try await SourceClient.fetchData(url: url, referer: referer)
                                guard let image = UIImage(data: raw) else { return (start + offset, nil) }
                                return (start + offset, image.jpegData(compressionQuality: 0.85))
                            } catch {
                                return (start + offset, nil)
                            }
                        }
                    }
                    var collected: [(Int, Data?)] = []
                    for await result in group { collected.append(result) }
                    return collected.sorted { $0.0 < $1.0 }
                }

                for (_, data) in fetched {
                    guard let data else {
                        failedCount += 1
                        continue
                    }
                    index += 1
                    entries.append((String(format: "%05d.jpg", index), data))
                }
                statusText = "第 \(chapterIndex + 1)/\(list.count) 章 · 已取 \(min(end, targets.count))/\(targets.count) 张"
            }

            progress = Double(chapterIndex + 1) / Double(list.count)
        }

        if entries.isEmpty {
            finishedMessage = "一张图都没下载下来，检查 content.images 规则或站点是否限制访问"
            return nil
        }

        let name = Self.safeName(item.name)
        let dest = uniqueURL(name: name, ext: "cbz", dir: shelf.booksDir)
        let data = MiniZip.make(entries: entries)

        guard (try? data.write(to: dest, options: .atomic)) != nil else {
            finishedMessage = "写文件失败"
            return nil
        }

        shelf.scan()
        let saved = shelf.books.first { $0.fileName == dest.lastPathComponent }
        if let saved {
            shelf.attachProvenance(
                bookID: saved.id,
                sourceID: source.id,
                sourceLink: item.link,
                sourceName: source.name,
                chapterCount: list.count,
                latestChapter: list.last?.name ?? ""
            )
        }
        finishedMessage = failedCount > 0
            ? "已保存到书架：\(entries.count) 页（\(failedCount) 张失败）"
            : "已保存到书架：\(entries.count) 页"
        return saved
    }

    // MARK: - 诊断

    /// 给书源编辑页用：跑一次搜索，把结果或报错原文吐出来
    func diagnose(source: BookSource, keyword: String) async -> String {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return "先输入一个测试关键词" }
        do {
            let items = try await SourceClient.search(source: source, keyword: text)
            let sample = items.prefix(3).map { "\($0.name)\($0.author.isEmpty ? "" : "（\($0.author)）")" }
            return "命中 \(items.count) 条：\n" + sample.joined(separator: "\n")
        } catch let failure as SourceFailure {
            return "失败：\(failure.message)"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 工具

    static func safeName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var name = raw.components(separatedBy: invalid).joined(separator: "_")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 60 { name = String(name.prefix(60)) }
        return name.isEmpty ? "未命名" : name
    }

    private func uniqueURL(name: String, ext: String, dir: URL) -> URL {
        var candidate = dir.appendingPathComponent("\(name).\(ext)")
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name)_\(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
