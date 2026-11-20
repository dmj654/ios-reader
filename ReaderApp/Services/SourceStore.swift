//
//  SourceStore.swift
//  ReaderApp
//
//  书源仓库：增删改、导入（粘贴 / 文件 / 地址）、持久化
//

import Foundation
import SwiftUI

@MainActor
final class SourceStore: ObservableObject {

    @Published var sources: [BookSource] = []
    @Published var lastError: String?

    private var storeURL: URL {
        sourcesDir.appendingPathComponent("sources.json")
    }

    private var backupURL: URL {
        sourcesDir.appendingPathComponent("sources.backup.json")
    }

    /// v1.8.2：书源搬进 Documents/Sources/ 子目录。
    /// 以前放在 Documents 根目录，而书架的「扫描松散文件」会把根目录里所有认得出的文件
    /// 收进书架 —— 于是 sources.json 被当成 TXT 改名叫 sources.txt 搬进 Books/，
    /// 结果：书架里多出一本「书源」，同时书源文件不见了（下次启动就读不到书源）。
    private var sourcesDir: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Sources", isDirectory: true)
        if fm.fileExists(atPath: dir.path) == false {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var legacyStoreURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sources.json")
    }

    private var legacyBackupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sources.backup.json")
    }

    init() {
        load()
    }

    var enabledSources: [BookSource] {
        sources.filter { $0.enabled && $0.baseUrl.isEmpty == false && $0.search.list.isEmpty == false }
    }

    // MARK: - 持久化

    /// 读：永远不因为读不出来就清空用户的书源
    func load() {
        let manager = FileManager.default

        migrateLegacyFiles()

        if let decoded = SourceStore.decodeTolerant(storeURL) {
            sources = decoded
            return
        }

        // 主文件没有或者读坏了，先试备份
        if let decoded = SourceStore.decodeTolerant(backupURL) {
            sources = decoded
            lastError = "书源主文件读取失败，已用备份恢复（\(decoded.count) 条）"
            save()
            return
        }

        // 再试「被书架误收走」的那份（v1.8.2 之前的 bug 会把书源文件改名搬进 Books/）
        if let recovered = recoverFromBooksFolder() {
            sources = recovered
            save()
            lastError = "已从书架里被误收的文件恢复 \(recovered.count) 条书源"
            return
        }

        if manager.fileExists(atPath: storeURL.path) {
            // 文件在，但一条都读不出来：保留文件，不清空、不覆盖
            sources = []
            lastError = "书源文件读不出来，已保留原文件未覆盖。可以到「书源管理」重新导入。"
            return
        }

        // 真正的首次启动
        sources = [SourceStore.seedTemplate]
        save()
    }

    /// 把老位置（Documents 根目录）的文件搬进 Sources/ 子目录
    private func migrateLegacyFiles() {
        let fm = FileManager.default
        let pairs: [(URL, URL)] = [(legacyStoreURL, storeURL), (legacyBackupURL, backupURL)]
        for (old, new) in pairs {
            guard fm.fileExists(atPath: old.path) else { continue }
            if fm.fileExists(atPath: new.path) {
                // 新位置已有内容，老文件改名留档，绝不直接删（可能是用户唯一的备份）
                let archived = sourcesDir.appendingPathComponent(
                    new.lastPathComponent.replacingOccurrences(of: ".json", with: ".legacy.json")
                )
                try? fm.removeItem(at: archived)
                try? fm.moveItem(at: old, to: archived)
                continue
            }
            if (try? fm.moveItem(at: old, to: new)) == nil {
                if let data = try? Data(contentsOf: old) {
                    try? data.write(to: new, options: .atomic)
                    try? fm.removeItem(at: old)
                }
            }
        }
    }

    /// 从 Books 目录里找回被误当成书的书源文件
    private func recoverFromBooksFolder() -> [BookSource]? {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let booksDir = docs.appendingPathComponent("Books")
        guard let names = try? fm.contentsOfDirectory(atPath: booksDir.path) else { return nil }

        for name in names {
            let lower = name.lowercased()
            // 只碰「看起来是书源」的文件：sources.json / sources.txt / sources_1.txt 之类
            guard lower.hasPrefix("sources") else { continue }
            guard lower.hasSuffix(".json") || lower.hasSuffix(".txt") else { continue }

            let url = booksDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), data.isEmpty == false else { continue }

            if let decoded = SourceStore.decodeTolerant(data: data), decoded.isEmpty == false {
                moveBack(url: url, fm: fm)
                return decoded
            }

            if let text = String(data: data, encoding: .utf8),
               let converted = try? LegadoBridge.convert(text),
               converted.sources.isEmpty == false {
                moveBack(url: url, fm: fm)
                return converted.sources
            }
        }
        return nil
    }

    private func moveBack(url: URL, fm: FileManager) {
        let target = sourcesDir.appendingPathComponent("sources.recovered.json")
        try? fm.removeItem(at: target)
        if (try? fm.moveItem(at: url, to: target)) == nil, let data = try? Data(contentsOf: url) {
            try? data.write(to: target, options: .atomic)
            try? fm.removeItem(at: url)
        }
    }

    /// 宽容解码：整份失败就逐条解，坏的那条跳过，别牵连其他书源
    nonisolated static func decodeTolerant(_ url: URL) -> [BookSource]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeTolerant(data: data)
    }

    nonisolated static func decodeTolerant(data: Data) -> [BookSource]? {
        guard data.isEmpty == false else { return nil }

        if let list = try? JSONDecoder().decode([BookSource].self, from: data) {
            return list
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }

        var output: [BookSource] = []
        for item in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { continue }
            if let source = try? JSONDecoder().decode(BookSource.self, from: itemData) {
                output.append(source)
            }
        }
        return output
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(sources) else {
            lastError = "书源序列化失败，这次改动可能没存上"
            return
        }

        // 旧文件先留一份备份，再写新的
        if let old = try? Data(contentsOf: storeURL), old.isEmpty == false {
            try? old.write(to: backupURL, options: .atomic)
        }

        do {
            try data.write(to: storeURL, options: .atomic)
        } catch {
            lastError = "书源写入失败：\(error.localizedDescription)"
            return
        }

        // 写完立刻读回来验一遍，确认下一次启动不会读不出来
        if let readBack = SourceStore.decodeTolerant(storeURL), readBack.count == sources.count {
            lastError = nil
        } else {
            lastError = "书源写入后校验不通过（\(sources.count) 条），下一次启动可能读不到"
        }
    }

    /// 导出：把当前全部书源吐成 JSON，方便换机 / 重装后恢复
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(sources),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    // MARK: - 增删改

    func add(_ newSources: [BookSource]) {
        sources.append(contentsOf: newSources)
        save()
    }

    func remove(_ source: BookSource) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    func setEnabled(_ source: BookSource, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].enabled = enabled
        save()
    }

    // MARK: - 批量操作（一千条源的时候必备）

    func setEnabled(ids: Set<UUID>, enabled: Bool) {
        guard ids.isEmpty == false else { return }
        var changed = false
        for index in sources.indices where ids.contains(sources[index].id) {
            if sources[index].enabled != enabled {
                sources[index].enabled = enabled
                changed = true
            }
        }
        if changed { save() }
    }

    func remove(ids: Set<UUID>) {
        guard ids.isEmpty == false else { return }
        let before = sources.count
        sources.removeAll { ids.contains($0.id) }
        if sources.count != before { save() }
    }

    /// 一次搜索结束后统一登记各源的结果，只写一次盘
    func applySearchOutcomes(_ outcomes: [UUID: Bool]) {
        guard outcomes.isEmpty == false else { return }
        let now = Date()
        for index in sources.indices {
            guard let success = outcomes[sources[index].id] else { continue }
            if success {
                sources[index].successCount += 1
                sources[index].lastSuccessAt = now
            } else {
                sources[index].failCount += 1
            }
            sources[index].lastUsedAt = now
        }
        save()
    }

    /// 全部分组（按出现次数从多到少），管理页用来做筛选菜单
    var groups: [String] {
        var counts: [String: Int] = [:]
        for source in sources {
            guard let group = source.group, group.isEmpty == false else { continue }
            counts[group, default: 0] += 1
        }
        return counts.keys.sorted { lhs, rhs in
            let l = counts[lhs] ?? 0
            let r = counts[rhs] ?? 0
            if l != r { return l > r }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// 编辑器保存：JSON 重新解析，保留原来的 id
    func update(_ source: BookSource, json: String) -> String? {
        do {
            var parsed = try SourceStore.decodeSource(json)
            parsed.id = source.id
            if let index = sources.firstIndex(where: { $0.id == source.id }) {
                sources[index] = parsed
                save()
                return nil
            }
            sources.append(parsed)
            save()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "JSON 格式不对：\(error.localizedDescription)"
        }
    }

    // MARK: - 导入

    struct ImportReport {
        var title: String
        var lines: [String]
    }

    struct ParseResult: @unchecked Sendable {
        var isLegado = false
        var sources: [BookSource] = []
        var notes: [String] = []
        var error: String?
    }

    nonisolated static func parseImport(_ text: String) -> ParseResult {
        var result = ParseResult()

        if LegadoBridge.looksLikeLegado(text) {
            result.isLegado = true
            do {
                let converted = try LegadoBridge.convert(text)
                result.sources = converted.sources
                result.notes = converted.notes
            } catch {
                result.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return result
        }

        do {
            result.sources = try SourceStore.decodeSources(text)
        } catch {
            result.error = (error as? LocalizedError)?.errorDescription ?? "JSON 格式不对：\(error.localizedDescription)"
        }
        return result
    }

    /// 导入（解析放到后台，避免大 JSON 卡住界面）
    func importPayload(_ text: String) async -> ImportReport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ImportReport(title: "没有内容", lines: ["粘贴框是空的"])
        }

        let parsed = await Task.detached(priority: .userInitiated) { () -> ParseResult in
            SourceStore.parseImport(trimmed)
        }.value

        return applyImport(parsed)
    }

    func importFilePayload(at url: URL) async -> ImportReport {
        guard let data = try? Data(contentsOf: url) else {
            return ImportReport(title: "读不出来", lines: ["文件打不开，换个位置再试"])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ImportReport(title: "读不出来", lines: ["文件不是 UTF-8 文本"])
        }

        // 选择器 asCopy 会把副本落进 App 沙盒，读完就删，
        // 否则这份 JSON 会被书架的「松散文件扫描」当成一本书收进去
        SourceStore.removeSandboxCopy(of: url)

        return await importPayload(text)
    }

    /// 只删落在 Inbox / tmp 里的选择器副本，用户原文件绝不碰
    nonisolated static func removeSandboxCopy(of url: URL) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let inbox = docs + "/Inbox"
        let tmp = fm.temporaryDirectory.path
        guard url.path.hasPrefix(inbox) || url.path.hasPrefix(tmp) else { return }
        try? fm.removeItem(at: url)
    }

    @discardableResult
    func applyImport(_ parsed: ParseResult) -> ImportReport {
        if let error = parsed.error {
            return ImportReport(title: "导入失败", lines: [error])
        }

        guard parsed.sources.isEmpty == false else {
            var lines = ["没有解析到可用的书源"]
            lines.append(contentsOf: parsed.notes)
            return ImportReport(title: "没有导入成功", lines: lines)
        }

        if parsed.isLegado {
            sources.append(contentsOf: parsed.sources)
            save()

            let novelCount = parsed.sources.filter { $0.type == .novel }.count
            let comicCount = parsed.sources.filter { $0.type == .comic }.count

            var lines: [String] = ["小说 \(novelCount) 条、漫画 \(comicCount) 条，已启用。"]
            for source in parsed.sources {
                let problems = SourceStore.problems(for: source)
                if problems.isEmpty == false {
                    lines.append("「\(source.name)」还缺：\(problems.joined(separator: "、"))")
                }
            }
            lines.append(contentsOf: parsed.notes)
            if let error = lastError { lines.append("⚠︎ \(error)") }
            return ImportReport(title: "已导入 \(parsed.sources.count) 条 Legado 书源", lines: lines)
        }

        // 本 App 格式：规则不全的不入库，把缺什么原样列出来
        var accepted: [BookSource] = []
        var rejected: [String] = []
        for source in parsed.sources {
            let problems = SourceStore.problems(for: source)
            if problems.isEmpty {
                accepted.append(source)
            } else {
                rejected.append("「\(source.name)」：\(problems.joined(separator: "、"))")
            }
        }

        guard accepted.isEmpty == false else {
            var lines = ["规则不完整，一条都没导入。"]
            lines.append(contentsOf: rejected)
            return ImportReport(title: "没有导入成功", lines: lines)
        }

        sources.append(contentsOf: accepted)
        save()

        var lines = rejected
        if let error = lastError { lines.append("⚠︎ \(error)") }
        return ImportReport(title: "已导入 \(accepted.count) 条", lines: lines)
    }

    func importFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return "文件读不出来" }
        guard let text = String(data: data, encoding: .utf8) else { return "文件不是 UTF-8 文本" }
        let report = applyImport(SourceStore.parseImport(text))
        return ([report.title] + report.lines).joined(separator: "\n")
    }

    /// 保留给旧调用点
    func importText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "内容为空" }
        let report = applyImport(SourceStore.parseImport(trimmed))
        if report.lines.isEmpty { return nil }
        return ([report.title] + report.lines).joined(separator: "\n")
    }

    /// 从网络地址拉一个书源 JSON
    func importRemote(_ link: String) async -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            return "地址不合法"
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else { return "返回内容不是文本" }
            return importText(text)
        } catch {
            return "下载失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 解析

    nonisolated static func decodeSources(_ text: String) throws -> [BookSource] {
        guard let data = text.data(using: .utf8) else {
            throw SourceFailure(message: "内容不是文本")
        }

        // 先认出别的软件的格式，直接说清楚，别让它装成一条空规则混进来
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let legado = SourceStore.detectLegado(object) {
                throw SourceFailure(message: legado)
            }
        }

        if let list = try? JSONDecoder().decode([BookSource].self, from: data) {
            return list
        }
        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawList = wrapper["sources"] {
            let rawData = try JSONSerialization.data(withJSONObject: rawList)
            return try JSONDecoder().decode([BookSource].self, from: rawData)
        }
        let single = try JSONDecoder().decode(BookSource.self, from: data)
        return [single]
    }

    /// 识别「阅读 / Legado」书源，返回给用户看的说明
    nonisolated static func detectLegado(_ object: Any) -> String? {
        let keys = ["ruleSearch", "bookSourceUrl", "bookSourceName", "searchUrl", "ruleToc", "ruleBookInfo", "ruleContent"]
        var found = false

        if let dict = object as? [String: Any] {
            found = keys.contains { dict[$0] != nil }
        } else if let list = object as? [Any] {
            found = list.contains { item in
                guard let dict = item as? [String: Any] else { return false }
                return keys.contains { dict[$0] != nil }
            }
        }

        guard found else { return nil }
        return """
        这是「阅读 / Legado」格式的书源，本 App 用的是自己的精简规则格式，字段对不上，导入也跑不起来。

        两个办法：
        1. 把你的书源 JSON 发给我，我按本 App 的格式改一条给你（能用的话直接贴回来导入）；
        2. 自己写：书源管理 →「规则怎么写」，里面有完整模板和语法。
        """
    }

    /// 缺什么就列什么，导入和列表都用它
    nonisolated static func problems(for source: BookSource) -> [String] {
        var problems: [String] = []

        if source.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("缺名字") }
        if source.baseUrl.lowercased().hasPrefix("http") == false { problems.append("baseUrl 不是 http 地址") }

        if source.search.url.isEmpty { problems.append("缺 search.url") }
        if source.search.list.isEmpty { problems.append("缺 search.list") }
        if source.search.name.isEmpty { problems.append("缺 search.name") }
        if source.search.link.isEmpty { problems.append("缺 search.link") }

        if source.chapters.list.isEmpty { problems.append("缺 chapters.list") }
        if source.chapters.name.isEmpty { problems.append("缺 chapters.name") }
        if source.chapters.link.isEmpty { problems.append("缺 chapters.link") }

        switch source.type {
        case .novel:
            if source.content.text.isEmpty { problems.append("缺 content.text") }
        case .comic:
            if source.content.images.isEmpty { problems.append("缺 content.images") }
        }

        return problems
    }

    /// 建一条新书源：带模板、未启用，直接进编辑器
    func addTemplate(_ type: SourceType) -> BookSource {
        var source = type == .novel ? BookSource.novelTemplate : BookSource.comicTemplate
        source.name = type == .novel ? "新小说源" : "新漫画源"
        source.baseUrl = ""
        source.enabled = false
        sources.append(source)
        save()
        return source
    }

    var novelSources: [BookSource] { sources.filter { $0.type == .novel } }
    var comicSources: [BookSource] { sources.filter { $0.type == .comic } }

    nonisolated static func decodeSource(_ text: String) throws -> BookSource {
        // 编辑器里直接粘一条 Legado 书源也能测
        if LegadoBridge.looksLikeLegado(text) {
            let (sources, _) = try LegadoBridge.convert(text)
            guard let first = sources.first else {
                throw SourceFailure(message: "这份 Legado 书源里没有能用的条目")
            }
            return first
        }
        let list = try decodeSources(text)
        guard let first = list.first else { throw SourceFailure(message: "没有书源内容") }
        return first
    }

    // MARK: - 初始示例（未启用，只用来示范格式）

    static var seedTemplate: BookSource {
        var source = BookSource(
            name: "示例源（改规则后启用）",
            type: .novel,
            baseUrl: "https://www.example.com",
            search: SearchRule(
                url: "/search.php?q={{key}}&page={{page}}",
                list: "css:ul.book-list li",
                name: "css:a.title@text",
                author: "css:span.author@text",
                cover: "css:img@src",
                link: "css:a.title@href"
            ),
            chapters: ChapterRule(
                url: "{{link}}",
                list: "css:#chapterlist li",
                name: "css:a@text",
                link: "css:a@href"
            ),
            content: ContentRule(
                url: "{{link}}",
                text: "css:#content@text",
                images: "css:#images img@src",
                remove: ["css:.ad", "css:script", "css:style"],
                removeLines: ["请记住本站", "^章节错误.*$"]
            )
        )
        source.enabled = false
        return source
    }
}
