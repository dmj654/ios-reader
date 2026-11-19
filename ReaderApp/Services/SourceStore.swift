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
            sources.append(contentsOf: imported)
            save()
            return nil
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
