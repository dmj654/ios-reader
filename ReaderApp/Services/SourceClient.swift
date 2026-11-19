//
//  SourceClient.swift
//  ReaderApp
//
//  按书源规则上网抓：搜索 → 目录 → 正文 / 漫画图
//

import Foundation
import SwiftSoup

struct SourceFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum SourceClient {

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // MARK: - 请求

    static func expand(_ template: String, keyword: String, page: Int, link: String, base: String) -> String {
        var text = template
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? keyword
        text = text.replacingOccurrences(of: "{{key}}", with: encodedKeyword)
        text = text.replacingOccurrences(of: "{{keyRaw}}", with: keyword)
        text = text.replacingOccurrences(of: "{{page}}", with: "\(page)")
        text = text.replacingOccurrences(of: "{{link}}", with: link)
        text = text.replacingOccurrences(of: "{{base}}", with: base)
        return text
    }

    static func fetchText(url: String, source: BookSource, method: String, body: String?,
                          referer: String?, extraHeaders: [String: String]) async throws -> String {
        guard let finalURL = URL(string: url) else {
            throw SourceFailure(message: "书源里的地址不合法：\(url)")
        }

        var request = URLRequest(url: finalURL)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        let refererValue = (referer?.isEmpty == false ? referer! : source.baseUrl)
        if refererValue.isEmpty == false {
            request.setValue(refererValue, forHTTPHeaderField: "Referer")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if method.uppercased() == "POST" {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = (body ?? "").data(using: .utf8)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw SourceFailure(message: "服务器返回 \(http.statusCode)")
            }
            guard let text = TextLoader.decode(data), text.isEmpty == false else {
                throw SourceFailure(message: "页面内容为空")
            }
            return text
        } catch let error as SourceFailure {
            throw error
        } catch {
            throw SourceFailure(message: "网络请求失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 搜索

    static func search(source: BookSource, keyword: String, page: Int = 1) async throws -> [SourceItem] {
        let rule = source.search
        let rawVar = expand(rule.url, keyword: keyword, page: page, link: "", base: source.baseUrl)
        let url = RuleParser.absolutize(rawVar, base: source.baseUrl)
        let body = rule.body.map { expand($0, keyword: keyword, page: page, link: "", base: source.baseUrl) }

        let html = try await fetchText(
            url: url,
            source: source,
            method: rule.method,
            body: body,
            referer: source.baseUrl,
            extraHeaders: rule.headers
        )

        guard let root = RuleParser.parseHTML(html) else {
            throw SourceFailure(message: "页面解析失败")
        }

        let listNodes = RuleParser.nodes(rule.list, in: root, base: url)
        if listNodes.isEmpty {
            throw SourceFailure(message: "搜索页里没有匹配「\(rule.list)」的内容，可能是站点改版或规则写错")
        }

        var items: [SourceItem] = []
        var seen = Set<String>()

        for node in listNodes {
            guard let name = RuleParser.string(rule.name, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.isEmpty == false else { continue }
            guard let link = RuleParser.string(rule.link, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.isEmpty == false else { continue }
            if seen.contains(link) { continue }
            seen.insert(link)

            let author = RuleParser.string(rule.author, in: node, base: url) ?? ""
            let cover = RuleParser.string(rule.cover, in: node, base: url) ?? ""

            items.append(
                SourceItem(
                    name: name,
                    author: author,
                    cover: cover,
                    link: link,
                    sourceID: source.id,
                    sourceName: source.name,
                    type: source.type
                )
            )
        }

        if items.isEmpty {
            throw SourceFailure(message: "搜索到了页面，但提取不到书名，检查 name / link 规则")
        }
        return items
    }

    // MARK: - 目录

    static func chapters(source: BookSource, item: SourceItem) async throws -> [SourceChapter] {
        let rule = source.chapters
        let rawVar = expand(rule.url, keyword: item.name, page: 1, link: item.link, base: source.baseUrl)
        let url = RuleParser.absolutize(rawVar, base: item.link.isEmpty ? source.baseUrl : item.link)

        let html = try await fetchText(url: url, source: source, method: "GET", body: nil,
                                       referer: item.link, extraHeaders: [:])

        guard let root = RuleParser.parseHTML(html) else {
            throw SourceFailure(message: "目录页解析失败")
        }

        let listNodes = RuleParser.nodes(rule.list, in: root, base: url)
        if listNodes.isEmpty {
            throw SourceFailure(message: "目录页里没有匹配「\(rule.list)」的内容")
        }

        var chapters: [SourceChapter] = []
        var seen = Set<String>()
        for node in listNodes {
            guard let name = RuleParser.string(rule.name, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let link = RuleParser.string(rule.link, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.isEmpty == false else { continue }
            if seen.contains(link) { continue }
            seen.insert(link)
            chapters.append(SourceChapter(name: name.isEmpty ? "第 \(chapters.count + 1) 章" : name, link: link))
        }

        if chapters.isEmpty {
            throw SourceFailure(message: "提取不到章节，检查 chapters 里的 name / link 规则")
        }
        return chapters
    }

    // MARK: - 正文

    static func chapterText(source: BookSource, chapter: SourceChapter) async throws -> String {
        let rule = source.content
        let rawVar = expand(rule.url, keyword: "", page: 1, link: chapter.link, base: source.baseUrl)
        let url = RuleParser.absolutize(rawVar, base: chapter.link)

        let html = try await fetchText(url: url, source: source, method: "GET", body: nil,
                                       referer: chapter.link, extraHeaders: [:])

        guard let document = try? SwiftSoup.parse(html) else {
            throw SourceFailure(message: "章节页解析失败")
        }

        for selector in rule.remove {
            let css = selector.hasPrefix("css:") ? String(selector.dropFirst(4)) : selector
            if let elements = try? document.select(css) {
                for element in elements.array() {
                    try? element.remove()
                }
            }
        }

        let root = RuleNode.html(document)
        guard var text = RuleParser.string(rule.text, in: root, base: url) else {
            throw SourceFailure(message: "取不到正文，检查 content.text 规则")
        }

        text = cleanLines(text, patterns: rule.removeLines)
        if text.count < 20 {
            throw SourceFailure(message: "正文太短（\(text.count) 字），可能是站点换了正文容器")
        }
        return text
    }

    static func chapterImages(source: BookSource, chapter: SourceChapter) async throws -> [String] {
        let rule = source.content
        let rawVar = expand(rule.url, keyword: "", page: 1, link: chapter.link, base: source.baseUrl)
        let url = RuleParser.absolutize(rawVar, base: chapter.link)

        let html = try await fetchText(url: url, source: source, method: "GET", body: nil,
                                       referer: chapter.link, extraHeaders: [:])

        guard let root = RuleParser.parseHTML(html) else {
            throw SourceFailure(message: "章节页解析失败")
        }

        var images = RuleParser.strings(rule.images, in: root, base: url)

        // 懒加载站点的兼容：@src 取不到时试常见懒加载属性
        if images.isEmpty, rule.images.contains("@src") {
            for fallback in ["@attr(data-src)", "@attr(data-original)", "@attr(data-lazy-src)", "@attr(data-echo)"] {
                let rule2 = rule.images.replacingOccurrences(of: "@src", with: fallback)
                images = RuleParser.strings(rule2, in: root, base: url)
                if images.isEmpty == false { break }
            }
        }

        images = images.filter { $0.hasPrefix("http") }
        if images.isEmpty {
            throw SourceFailure(message: "这一章没取到图片，检查 content.images 规则")
        }
        return images
    }

    // MARK: - 图片下载

    static func fetchData(url: String, referer: String) async throws -> Data {
        guard let finalURL = URL(string: url) else {
            throw SourceFailure(message: "图片地址不合法")
        }
        var request = URLRequest(url: finalURL)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if referer.isEmpty == false {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw SourceFailure(message: "图片返回 \(http.statusCode)")
            }
            return data
        } catch let error as SourceFailure {
            throw error
        } catch {
            throw SourceFailure(message: "图片下载失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 逐级诊断

    enum DebugStage: String, CaseIterable, Identifiable {
        case search, chapters, content

        var id: String { rawValue }

        var title: String {
            switch self {
            case .search: return "搜索"
            case .chapters: return "目录"
            case .content: return "正文"
            }
        }
    }

    struct DebugOutput {
        var detail: String
        var html: String
        var pageURL: String
    }

    static func debug(source: BookSource, keyword: String, stage: DebugStage) async -> DebugOutput {
        do {
            switch stage {
            case .search:
                return try await debugSearch(source: source, keyword: keyword)

            case .chapters:
                let found = try await firstItem(source: source, keyword: keyword)
                let detailURL = RuleParser.absolutize(
                    expand(source.chapters.url, keyword: keyword, page: 1, link: found.link, base: source.baseUrl),
                    base: found.link
                )
                let html = try await fetchText(url: detailURL, source: source, method: "GET", body: nil,
                                               referer: found.link, extraHeaders: [:])
                guard let root = RuleParser.parseHTML(html) else {
                    return DebugOutput(detail: "目录页解析失败", html: html, pageURL: detailURL)
                }
                let nodes = RuleParser.nodes(source.chapters.list, in: root, base: detailURL)
                var lines = ["请求：\(detailURL)", "章节节点：\(nodes.count) 个"]
                if nodes.isEmpty {
                    lines.append("没有匹配到章节 → 检查 chapters.list")
                } else {
                    let names = nodes.prefix(3).compactMap {
                        RuleParser.string(source.chapters.name, in: $0, base: detailURL)
                    }
                    let links = nodes.prefix(1).compactMap {
                        RuleParser.string(source.chapters.link, in: $0, base: detailURL)
                    }
                    lines.append("章节示例：\(names.joined(separator: " | "))")
                    lines.append("链接示例：\(links.first ?? "空")")
                }
                return DebugOutput(detail: lines.joined(separator: "\n"), html: html, pageURL: detailURL)

            case .content:
                let found = try await firstItem(source: source, keyword: keyword)
                let detailURL = RuleParser.absolutize(
                    expand(source.chapters.url, keyword: keyword, page: 1, link: found.link, base: source.baseUrl),
                    base: found.link
                )
                let detailHTML = try await fetchText(url: detailURL, source: source, method: "GET", body: nil,
                                                     referer: found.link, extraHeaders: [:])
                guard let detailRoot = RuleParser.parseHTML(detailHTML),
                      let firstNode = RuleParser.nodes(source.chapters.list, in: detailRoot, base: detailURL).first,
                      let chapterLink = RuleParser.string(source.chapters.link, in: firstNode, base: detailURL) else {
                    return DebugOutput(detail: "先取到目录：目录阶段没有拿到章节链接", html: detailHTML, pageURL: detailURL)
                }

                let chapterURL = RuleParser.absolutize(
                    expand(source.content.url, keyword: keyword, page: 1, link: chapterLink, base: source.baseUrl),
                    base: chapterLink
                )
                let html = try await fetchText(url: chapterURL, source: source, method: "GET", body: nil,
                                               referer: chapterLink, extraHeaders: [:])

                var lines = ["请求：\(chapterURL)"]

                if source.type == .comic {
                    guard let root = RuleParser.parseHTML(html) else {
                        return DebugOutput(detail: "章节页解析失败", html: html, pageURL: chapterURL)
                    }
                    var images = RuleParser.strings(source.content.images, in: root, base: chapterURL)
                    if images.isEmpty, source.content.images.contains("@src") {
                        for fallback in ["@attr(data-src)", "@attr(data-original)", "@attr(data-lazy-src)"] {
                            images = RuleParser.strings(
                                source.content.images.replacingOccurrences(of: "@src", with: fallback),
                                in: root,
                                base: chapterURL
                            )
                            if images.isEmpty == false { break }
                        }
                    }
                    lines.append("图片：\(images.count) 张")
                    lines.append("首张：\(images.first ?? "空")")
                } else {
                    guard let document = try? SwiftSoup.parse(html) else {
                        return DebugOutput(detail: "章节页解析失败", html: html, pageURL: chapterURL)
                    }
                    for selector in source.content.remove {
                        let css = selector.hasPrefix("css:") ? String(selector.dropFirst(4)) : selector
                        if let elements = try? document.select(css) {
                            for element in elements.array() { try? element.remove() }
                        }
                    }
                    let root = RuleNode.html(document)
                    let text = RuleParser.string(source.content.text, in: root, base: chapterURL) ?? ""
                    lines.append("正文：\(text.count) 字")
                    lines.append("开头：\(text.prefix(60))")
                    if text.count < 20 {
                        lines.append("太短了 → 检查 content.text，或站点把正文放在别的容器里")
                    }
                }
                return DebugOutput(detail: lines.joined(separator: "\n"), html: html, pageURL: chapterURL)
            }
        } catch let failure as SourceFailure {
            return DebugOutput(detail: "失败：\(failure.message)", html: "", pageURL: "")
        } catch {
            return DebugOutput(detail: "失败：\(error.localizedDescription)", html: "", pageURL: "")
        }
    }

    private static func debugSearch(source: BookSource, keyword: String) async throws -> DebugOutput {
        let rule = source.search
        let url = RuleParser.absolutize(
            expand(rule.url, keyword: keyword, page: 1, link: "", base: source.baseUrl),
            base: source.baseUrl
        )
        let body = rule.body.map { expand($0, keyword: keyword, page: 1, link: "", base: source.baseUrl) }
        let html = try await fetchText(url: url, source: source, method: rule.method, body: body,
                                       referer: source.baseUrl, extraHeaders: rule.headers)

        guard let root = RuleParser.parseHTML(html) else {
            return DebugOutput(detail: "请求：\(url)\n页面解析失败", html: html, pageURL: url)
        }
        let nodes = RuleParser.nodes(rule.list, in: root, base: url)
        var lines = ["请求：\(url)", "搜索节点：\(nodes.count) 个"]
        if nodes.isEmpty {
            lines.append("没有匹配到列表 → 检查 search.list")
        } else {
            let names = nodes.prefix(3).compactMap { RuleParser.string(rule.name, in: $0, base: url) }
            let links = nodes.prefix(1).compactMap { RuleParser.string(rule.link, in: $0, base: url) }
            lines.append("书名示例：\(names.joined(separator: " | "))")
            lines.append("链接示例：\(links.first ?? "空")")
        }
        return DebugOutput(detail: lines.joined(separator: "\n"), html: html, pageURL: url)
    }

    private static func firstItem(source: BookSource, keyword: String) async throws -> SourceItem {
        let items = try await search(source: source, keyword: keyword)
        guard let first = items.first else {
            throw SourceFailure(message: "搜索没有结果，先修好搜索阶段")
        }
        return first
    }

    // MARK: - 清理

    static func cleanLines(_ text: String, patterns: [String]) -> String {
        guard patterns.isEmpty == false else { return RuleParser.normalize(text) }
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        var kept: [String] = []
        for line in RuleParser.normalize(text).components(separatedBy: "\n") {
            var drop = false
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            for regex in regexes where regex.firstMatch(in: line, range: range) != nil {
                drop = true
                break
            }
            if drop == false { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }
}
