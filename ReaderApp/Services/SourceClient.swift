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
                          referer: String?, extraHeaders: [String: String],
                          timeout: Double = 20) async throws -> String {
        guard let finalURL = URL(string: url) else {
            throw SourceFailure(message: "书源里的地址不合法：\(url)")
        }

        var request = URLRequest(url: finalURL)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        let refererValue = (referer?.isEmpty == false ? referer! : source.baseUrl)
        if refererValue.isEmpty == false {
            request.setValue(refererValue, forHTTPHeaderField: "Referer")
        }
        // 书源自带的头（Legado 的 header：UA / Cookie 等）
        for (key, value) in source.headers {
            if key.lowercased() == "referer" { continue }
            request.setValue(value, forHTTPHeaderField: key)
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

    static func search(source: BookSource, keyword: String, page: Int = 1, timeout: Double = 12) async throws -> [SourceItem] {
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
            extraHeaders: rule.headers,
            timeout: timeout
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

    /// 从一组节点里提取书单（搜索 / 发现共用）
    private static func parseItems(rule: SearchRule, root: RuleNode, base: String, source: BookSource) -> [SourceItem] {
        let listNodes = RuleParser.nodes(rule.list, in: root, base: base)
        var items: [SourceItem] = []
        var seen = Set<String>()

        for node in listNodes {
            guard let name = RuleParser.string(rule.name, in: node, base: base)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.isEmpty == false else { continue }
            guard let link = RuleParser.string(rule.link, in: node, base: base)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.isEmpty == false else { continue }
            if seen.contains(link) { continue }
            seen.insert(link)

            let author = RuleParser.string(rule.author, in: node, base: base) ?? ""
            let cover = RuleParser.string(rule.cover, in: node, base: base) ?? ""

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
        return items
    }

    /// 发现页：按分类链接拉书单；发现规则优先，提取为空再回退搜索规则
    static func discover(source: BookSource, link: ExploreLink, page: Int = 1) async throws -> [SourceItem] {
        let rules: [SearchRule]
        if source.explore.list.isEmpty {
            rules = [source.search]
        } else {
            rules = [source.explore, source.search]
        }

        var lastError: Error?
        for rule in rules {
            let url = RuleParser.absolutize(link.url, base: source.baseUrl)
            do {
                let html = try await fetchText(
                    url: url,
                    source: source,
                    method: "GET",
                    body: nil,
                    referer: source.baseUrl,
                    extraHeaders: rule.headers
                )
                guard let root = RuleParser.parseHTML(html) else {
                    throw SourceFailure(message: "页面解析失败")
                }
                let items = parseItems(rule: rule, root: root, base: url, source: source)
                if items.isEmpty {
                    throw SourceFailure(message: "这个分类里提取不到书单，可能是站点改版或规则写错")
                }
                return items
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SourceFailure(message: "提取不到书单")
    }

    static func chapters(source: BookSource, item: SourceItem) async throws -> BookDetail {
        let rule = source.chapters
        let firstRaw = expand(rule.url, keyword: item.name, page: 1, link: item.link, base: source.baseUrl)
        var url = RuleParser.absolutize(firstRaw, base: item.link.isEmpty ? source.baseUrl : item.link)

        var chapters: [SourceChapter] = []
        var seen = Set<String>()
        var visited = Set<String>()
        var firstHTML = ""
        var page = 0
        let maxPages = 30

        while page < maxPages {
            let html = try await fetchText(url: url, source: source, method: "GET", body: nil,
                                           referer: item.link, extraHeaders: [:])
            if firstHTML.isEmpty { firstHTML = html }
            guard let root = RuleParser.parseHTML(html) else {
                if chapters.isEmpty { throw SourceFailure(message: "目录页解析失败") }
                break
            }

            let listNodes = RuleParser.nodes(rule.list, in: root, base: url)
            if chapters.isEmpty && listNodes.isEmpty {
                throw SourceFailure(message: "目录页里没有匹配「\(rule.list)」的内容")
            }

            var added = 0
            for node in listNodes {
                guard let name = RuleParser.string(rule.name, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let link = RuleParser.string(rule.link, in: node, base: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      link.isEmpty == false else { continue }
                if seen.contains(link) { continue }
                seen.insert(link)
                chapters.append(SourceChapter(name: name.isEmpty ? "第 \(chapters.count + 1) 章" : name, link: link))
                added += 1
            }

            // 目录分页：有下一页规则就继续翻；这一页没加新章就停，防死循环
            guard rule.nextUrl.isEmpty == false, added > 0, page + 1 < maxPages else { break }

            let nextRaw: String?
            if nextUrlIsRule(rule.nextUrl) {
                nextRaw = RuleParser.string(rule.nextUrl, in: root, base: url)
            } else {
                nextRaw = expand(rule.nextUrl, keyword: item.name, page: page + 2, link: item.link, base: source.baseUrl)
            }
            guard let nextRaw, nextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { break }
            let nextURL = RuleParser.absolutize(nextRaw, base: url)
            guard visited.contains(nextURL) == false, nextURL != url else { break }
            visited.insert(nextURL)
            url = nextURL
            page += 1
        }

        if chapters.isEmpty {
            throw SourceFailure(message: "提取不到章节，检查 chapters 里的 name / link 规则")
        }

        let meta = extractMeta(html: firstHTML, chapters: chapters)
        return BookDetail(chapters: chapters, meta: meta)
    }

    /// nextTocUrl 是一条取值规则，还是纯地址模板
    private static func nextUrlIsRule(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("@") { return true }
        let prefixes = ["css:", "class.", "id.", "tag.", "@css:", "@xpath:", "@XPath:",
                        "regex:", "json:", "$.", "$[", "//"]
        return prefixes.contains { t.hasPrefix($0) }
    }

    /// 从详情页 HTML 里捞简介、状态、字数；规则没有的就靠常见容器名兜底
    private static func extractMeta(html: String, chapters: [SourceChapter]) -> BookMeta {
        var meta = BookMeta()
        meta.latestChapter = chapters.last?.name ?? ""

        guard let doc = try? SwiftSoup.parse(html) else { return meta }

        let introSelectors = [
            "#intro", ".intro", "#description", ".description", ".book-intro",
            ".book-summary", ".summary", ".desc", "#bookIntro", ".book-info .intro",
            ".book-detail .intro", ".book-intro p", ".book-info .desc"
        ]
        for selector in introSelectors {
            if let element = try? doc.select(selector).first(),
               let text = try? element.text(),
               text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 {
                meta.intro = cleanedIntro(text)
                break
            }
        }
        if meta.intro.isEmpty,
           let tag = try? doc.select("meta[name=description]").first(),
           let content = try? tag.attr("content"),
           content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 {
            meta.intro = cleanedIntro(content)
        }

        let bodyText = (try? doc.body()?.text()) ?? ""

        for keyword in ["已完结", "完结", "全本", "连载中", "连载", "暂停更新", "断更", "出版"] {
            if bodyText.contains(keyword) {
                meta.status = keyword
                break
            }
        }

        if let word = firstRegex(in: bodyText, pattern: "(\\d+(?:\\.\\d+)?万?)字") {
            meta.wordCount = word
        }

        return meta
    }

    private static func cleanedIntro(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r", with: " ")
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstRegex(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    // MARK: - 正文

    static func chapterText(source: BookSource, chapter: SourceChapter) async throws -> String {
        let rule = source.content
        let firstRaw = expand(rule.url, keyword: "", page: 1, link: chapter.link, base: source.baseUrl)
        var url = RuleParser.absolutize(firstRaw, base: chapter.link)

        var collected: [String] = []
        var visited = Set<String>()
        var page = 0
        let maxPages = 10

        while page < maxPages {
            let html = try await fetchText(url: url, source: source, method: "GET", body: nil,
                                           referer: chapter.link, extraHeaders: [:])

            guard let document = try? SwiftSoup.parse(html) else {
                if collected.isEmpty { throw SourceFailure(message: "章节页解析失败") }
                break
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
            var text = RuleParser.string(rule.text, in: root, base: url)

            // 规则没取到 / 取出来太短：按常见正文容器名兜底扫一遍
            if (text ?? "").count < 20, let fallback = fallbackContent(document: document) {
                text = fallback
            }

            guard var text = text else {
                if collected.isEmpty {
                    throw SourceFailure(message: "取不到正文，检查 content.text 规则（页面 \(html.count) 字）")
                }
                break
            }

            // Legado 的正文规则常以 @html 结尾，拿到的是标签，这里统一转成纯文本
            if text.contains("<") && text.contains(">") {
                text = RuleParser.plainText(html: text)
            }

            text = cleanLines(text, patterns: rule.removeLines)
            if text.count < 20, let fallback = fallbackContent(document: document) {
                text = cleanLines(fallback, patterns: rule.removeLines)
            }
            collected.append(text)

            // 章节分多页：按 nextContentUrl 继续翻，直到没有下一页
            guard rule.nextUrl.isEmpty == false else { break }
            let nextRaw: String?
            if nextUrlIsRule(rule.nextUrl) {
                nextRaw = RuleParser.string(rule.nextUrl, in: root, base: url)
            } else {
                nextRaw = expand(rule.nextUrl, keyword: "", page: page + 2, link: chapter.link, base: source.baseUrl)
            }
            guard let nextRaw, nextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { break }
            let nextURL = RuleParser.absolutize(nextRaw, base: url)
            guard visited.contains(nextURL) == false, nextURL != url else { break }
            visited.insert(nextURL)
            url = nextURL
            page += 1
        }

        let merged = collected.joined(separator: "\n")
        if merged.count < 20 {
            throw SourceFailure(message: "正文太短（\(merged.count) 字）；规则「\(rule.text)」可能没对上正文容器")
        }
        return merged
    }

    /// 规则没匹配上时，按常见小说站正文容器名兜底，挑中文最多的一块
    private static let fallbackContentSelectors = [
        "#content", ".content", "#chapter-content", ".chapter-content",
        "#chaptercontent", ".chaptercontent", "#BookText", ".BookText",
        "#novelcontent", ".novel-content", ".article-content", ".article",
        "article", ".read-content", ".readcontent", "#htmlContent",
        ".post-content", ".entry-content", ".txt", ".txt-content", "#nr1",
        ".nr1", ".chapter-body", ".text-content", "#contentbox", ".contentbox",
        ".main-content", ".book-content", "#chapterBody", ".chapterBody",
        ".novel_content", "#novel_content", ".chapter-content-body", "#BookContent",
        ".BookContent", "#chaptertext", ".chaptertext"
    ]

    private static func fallbackContent(document: Document) -> String? {
        var best = ""
        for selector in fallbackContentSelectors {
            guard let element = try? document.select(selector).first() else { continue }
            let raw = (try? element.outerHtml()) ?? ""
            let candidate = RuleParser.plainText(html: raw)
            if chineseCount(candidate) > chineseCount(best) { best = candidate }
        }
        // 再退一步：正文段落最多的直接子容器
        if chineseCount(best) < 20, let body = try? document.body() {
            for element in body.children().array() {
                let raw = (try? element.outerHtml()) ?? ""
                let candidate = RuleParser.plainText(html: raw)
                if chineseCount(candidate) > chineseCount(best) { best = candidate }
            }
        }
        return best.count >= 20 ? best : nil
    }

    private static func chineseCount(_ text: String) -> Int {
        text.reduce(0) { $1.isChinese ? $0 + 1 : $0 }
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

        // Legado 的图片规则有时以 @html 结尾，拿到的是 HTML 片段，从里面再抽一遍 src
        if images.isEmpty, let first = RuleParser.strings(rule.images, in: root, base: url).first,
           first.contains("<img") {
            for raw in RuleParser.strings(rule.images, in: root, base: url) {
                let found = RuleParser.regexMatches("<img[^>]+src=[\"']([^\"']+)[\"']", in: raw)
                images.append(contentsOf: found.map { RuleParser.absolutize($0, base: url) })
            }
            images = images.filter { $0.hasPrefix("http") }
        }

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
                lines.append(contentsOf: unsupportedNote([
                    ("chapters.list", source.chapters.list),
                    ("chapters.name", source.chapters.name),
                    ("chapters.link", source.chapters.link)
                ]))
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
                    lines.append(contentsOf: unsupportedNote([("content.text", source.content.text)]))
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
        var lines = ["请求：\(url)", "抓到的页面：\(html.count) 字", "搜索节点：\(nodes.count) 个"]
        if nodes.isEmpty {
            lines.append("没有匹配到列表 → 检查 search.list")
            let sample = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("页面正文开头：\(String(sample.prefix(140)))")
        } else {
            let names = nodes.prefix(3).compactMap { RuleParser.string(rule.name, in: $0, base: url) }
            let links = nodes.prefix(1).compactMap { RuleParser.string(rule.link, in: $0, base: url) }
            lines.append("书名示例：\(names.joined(separator: " | "))")
            lines.append("链接示例：\(links.first ?? "空")")
        }
        lines.append(contentsOf: unsupportedNote([
            ("search.list", rule.list),
            ("search.name", rule.name),
            ("search.link", rule.link)
        ]))
        return DebugOutput(detail: lines.joined(separator: "\n"), html: html, pageURL: url)
    }

    /// 这一段里有没有跑不了的规则，单独点出来
    private static func unsupportedNote(_ pairs: [(String, String)]) -> [String] {
        pairs.compactMap { label, rule in
            RuleParser.unsupportedReason(rule).map { "⚠︎ \(label)：\($0)" }
        }
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

private extension Character {
    var isChinese: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0x20000...0x2A6DF).contains(scalar.value)
    }
}
