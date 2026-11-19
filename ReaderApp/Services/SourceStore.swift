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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sources.json")
    }

    init() {
        load()
    }

    var enabledSources: [BookSource] {
        sources.filter { $0.enabled && $0.baseUrl.isEmpty == false && $0.search.list.isEmpty == false }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([BookSource].self, from: data) else {
            sources = [SourceStore.seedTemplate]
            save()
            return
        }
        sources = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(sources) else { return }
        try? data.write(to: storeURL, options: .atomic)
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

    /// 返回 nil 表示成功
    func importText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "内容为空" }
        do {
            let imported = try SourceStore.decodeSources(trimmed)
            guard imported.isEmpty == false else { return "没有解析到任何书源" }

            // 先校验，不合格的不入库，并把原因原样告诉用户
            var accepted: [BookSource] = []
            var rejected: [String] = []
            for source in imported {
                let problems = SourceStore.problems(for: source)
                if problems.isEmpty {
                    accepted.append(source)
                } else {
                    rejected.append("「\(source.name)」：\(problems.joined(separator: "、"))")
                }
            }

            if accepted.isEmpty {
                return "没有可用的书源，未导入。\n" + rejected.joined(separator: "\n")
            }

            sources.append(contentsOf: accepted)
            save()

            if rejected.isEmpty { return nil }
            return "已导入 \(accepted.count) 个，跳过 \(rejected.count) 个：\n" + rejected.joined(separator: "\n")
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "JSON 格式不对：\(error.localizedDescription)"
        }
    }

    func importFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return "文件读不出来" }
        guard let text = String(data: data, encoding: .utf8) else { return "文件不是 UTF-8 文本" }
        return importText(text)
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

    static func decodeSources(_ text: String) throws -> [BookSource] {
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
    static func detectLegado(_ object: Any) -> String? {
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
    static func problems(for source: BookSource) -> [String] {
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

    static func decodeSource(_ text: String) throws -> BookSource {
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
