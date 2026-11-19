//
//  LegadoBridge.swift
//  ReaderApp
//
//  把「阅读 / Legado」格式的书源 JSON 转成本 App的书源结构。
//  规则字符串原样保留，由 RuleParser 直接认 Legado 写法（CSS / 简化 XPath / JSON / ## 清理）。
//

import Foundation

enum LegadoBridge {

    private static let legadoKeys = ["ruleSearch", "bookSourceUrl", "bookSourceName",
                                     "searchUrl", "ruleToc", "ruleBookInfo", "ruleContent"]

    static func looksLikeLegado(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return detect(object)
    }

    static func detect(_ object: Any) -> Bool {
        if let dict = object as? [String: Any] {
            return legadoKeys.contains { dict[$0] != nil }
        }
        if let list = object as? [Any] {
            return list.contains { item in
                guard let dict = item as? [String: Any] else { return false }
                return legadoKeys.contains { dict[$0] != nil }
            }
        }
        return false
    }

    /// 返回：转换后的书源 + 给用户看的问题清单
    static func convert(_ text: String) throws -> (sources: [BookSource], notes: [String]) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            throw SourceFailure(message: "JSON 解析失败，检查是不是完整复制了")
        }

        var dicts: [[String: Any]] = []
        if let dict = object as? [String: Any] {
            if let list = dict["sources"] as? [Any] {
                dicts = list.compactMap { $0 as? [String: Any] }
            } else {
                dicts = [dict]
            }
        } else if let list = object as? [Any] {
            dicts = list.compactMap { $0 as? [String: Any] }
        }

        guard dicts.isEmpty == false else {
            throw SourceFailure(message: "没找到书源条目")
        }

        var sources: [BookSource] = []
        var notes: [String] = []

        for raw in dicts {
            let name = string(raw, "bookSourceName").isEmpty ? "未命名书源" : string(raw, "bookSourceName")
            let baseUrl = string(raw, "bookSourceUrl")

            let typeValue = (raw["bookSourceType"] as? NSNumber)?.intValue ?? 0
            if typeValue == 1 {
                notes.append("「\(name)」是听书源，本 App 只支持小说和漫画，已跳过")
                continue
            }
            if typeValue == 3 {
                notes.append("「\(name)」是文件型书源，已跳过")
                continue
            }
            let type: SourceType = typeValue == 2 ? .comic : .novel

            // 搜索地址（Legado 允许在地址后面跟 ,{"method":"POST","body":"..."}）
            var searchUrl = string(raw, "searchUrl")
            var method = "GET"
            var body: String? = nil

            if let found = searchUrl.range(of: ",(\\{.*\\})$", options: .regularExpression) {
                let jsonText = String(searchUrl[searchUrl.index(after: found.lowerBound)...])
                if let configData = jsonText.data(using: .utf8),
                   let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                    method = (config["method"] as? String)?.uppercased() ?? "GET"
                    body = config["body"] as? String
                    searchUrl = String(searchUrl[searchUrl.startIndex..<found.lowerBound])
                }
            }

            if searchUrl.isEmpty {
                notes.append("「\(name)」没有搜索地址（只有发现/分类），本 App 用不了，已跳过")
                continue
            }

            var headers: [String: String] = [:]
            if let parsed = raw["header"] as? [String: String] {
                headers = parsed
            } else if let anyDict = raw["header"] as? [String: Any] {
                for (key, value) in anyDict {
                    if let text = value as? String { headers[key] = text }
                }
            } else if let text = raw["header"] as? String,
                      let headerData = text.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
                headers = parsed
            }

            let searchMap = dictionary(raw, "ruleSearch")
            let tocMap = dictionary(raw, "ruleToc")
            let contentMap = dictionary(raw, "ruleContent")
            let infoMap = dictionary(raw, "ruleBookInfo")

            var listNodes = string(searchMap, "bookList")
            if listNodes.isEmpty { listNodes = string(infoMap, "init") }

            let contentRule = string(contentMap, "content")
            let imageRule = string(contentMap, "images").isEmpty ? contentRule : string(contentMap, "images")

            let converted = BookSource(
                name: name,
                type: type,
                baseUrl: baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl,
                search: SearchRule(
                    url: searchUrl,
                    method: method,
                    headers: headers,
                    body: body,
                    list: listNodes,
                    name: string(searchMap, "name"),
                    author: string(searchMap, "author"),
                    cover: string(searchMap, "coverUrl"),
                    link: string(searchMap, "bookUrl")
                ),
                chapters: ChapterRule(
                    url: string(infoMap, "tocUrl").isEmpty ? "{{link}}" : string(infoMap, "tocUrl"),
                    list: string(tocMap, "chapterList"),
                    name: string(tocMap, "chapterName"),
                    link: string(tocMap, "chapterUrl")
                ),
                content: ContentRule(
                    url: "{{link}}",
                    text: type == .novel ? contentRule : "",
                    images: type == .comic ? imageRule : ""
                ),
                headers: headers
            )

            // 这条规则能不能跑，先探一下，省得用户装了才发现是 JS
            var reason: String?
            for rule in [listNodes, string(searchMap, "name"), string(searchMap, "bookUrl"),
                         string(tocMap, "chapterList"), string(tocMap, "chapterName"),
                         string(tocMap, "chapterUrl"),
                         type == .novel ? contentRule : imageRule] {
                if let found = RuleParser.unsupportedReason(rule) {
                    reason = found
                    break
                }
            }

            if let reason {
                notes.append("「\(name)」里有规则跑不了：\(reason)。已导入，但要换规则才能用")
            }

            sources.append(converted)
        }

        return (sources, notes)
    }

    // MARK: - 取值小工具

    private static func string(_ dict: [String: Any], _ key: String) -> String {
        if let text = dict[key] as? String { return text }
        return ""
    }

    private static func dictionary(_ dict: [String: Any], _ key: String) -> [String: Any] {
        if let nested = dict[key] as? [String: Any] { return nested }
        if let text = dict[key] as? String,
           let data = text.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return nested
        }
        return [:]
    }
}
