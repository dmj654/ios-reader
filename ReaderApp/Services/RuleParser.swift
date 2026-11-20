//
//  RuleParser.swift
//  ReaderApp
//
//  规则解析器：把书源里的一行规则，跑成文本 / 链接 / 节点列表
//
//  支持两种写法：
//  1) 本 App 精简写法：css:选择器 / json:路径 / regex:正则 + @text/@html/@href/@src/@attr(x)
//  2) 阅读(Legado)写法：@css:选择器、class.名字、tag.名字、//XPath、$.JSON路径、
//     链式 @text/@html/@content/@href/@src/@tag.x/@css:x/@属性名，##正则##替换，|| 备用规则
//  说明：带 <js> / @js: 的规则跑不了（没有 JS 引擎），会明确报「不支持」。
//

import Foundation
import SwiftSoup

indirect enum RuleNode {
    case html(Element)
    case json(Any)
}

enum RuleParser {

    // MARK: - 类型

    private enum Kind: Equatable {
        case css, json, regex, xpath, js, unsupported
    }

    private enum Step {
        case text
        case html
        case href
        case src
        case attr(String)
        case descend(Kind, String)
        /// Legado 的 !N：取下标的第 N 个
        case index(Int)
    }

    private struct Part {
        var kind: Kind
        var path: String
        var steps: [Step]
    }

    private struct Spec {
        var parts: [Part] = []
        var replacements: [(String, String)] = []
        var unsupported: String?
    }

    // MARK: - 对外

    static func parseHTML(_ html: String) -> RuleNode? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        return .html(document)
    }

    /// 这条规则本 App 跑不跑得了；跑不了返回原因
    static func unsupportedReason(_ rule: String) -> String? {
        parse(rule).unsupported
    }

    /// 取一组节点（结果列表用）
    static func nodes(_ rule: String, in node: RuleNode, base: String) -> [RuleNode] {
        let spec = parse(rule)

        for part in spec.parts {
            var current: [RuleNode] = []

            switch part.kind {
            case .css:
                guard case .html(let root) = node else { continue }
                guard let elements = try? root.select(part.path) else { continue }
                current = elements.array().map { RuleNode.html($0) }

            case .json:
                guard case .json(let any) = node else { continue }
                for value in jsonValues(path: part.path, root: any) {
                    if let array = value as? [Any] {
                        current.append(contentsOf: array.map { RuleNode.json($0) })
                    } else {
                        current.append(.json(value))
                    }
                }

            default:
                continue
            }

            // 列表规则里的继续下钻：class.book-list@tag.li 这种写法全靠这一步
            for step in part.steps {
                switch step {
                case .descend(let kind, let sub):
                    guard kind == .css else { continue }
                    var next: [RuleNode] = []
                    for item in current {
                        guard case .html(let element) = item else { continue }
                        if let found = try? element.select(sub) {
                            next.append(contentsOf: found.array().map { RuleNode.html($0) })
                        }
                    }
                    current = next

                case .index(let n):
                    let idx = n == -1 ? current.count - 1 : n
                    current = (idx >= 0 && idx < current.count) ? [current[idx]] : []

                default:
                    continue
                }
            }

            if current.isEmpty == false { return current }
        }

        // 兜底：容器 class 改名了，但里面的标签还在（class.book-list@tag.li → 直接全局找 li）
        for part in spec.parts where part.kind == .css {
            guard case .html(let root) = node else { continue }
            for step in part.steps {
                guard case .descend(.css, let sub) = step else { continue }
                guard sub.isEmpty == false else { continue }
                if let found = try? root.select(sub), found.array().isEmpty == false {
                    return found.array().map { RuleNode.html($0) }
                }
            }
        }

        return []
    }

    /// 取一组字符串（图片列表用）
    static func strings(_ rule: String, in node: RuleNode, base: String) -> [String] {
        let spec = parse(rule)
        guard rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return [] }

        var output: [String] = []
        for part in spec.parts {
            let values = evaluate(part, in: node, base: base)
            if values.isEmpty { continue }
            output = values
            break
        }

        for (pattern, template) in spec.replacements {
            output = output.map { applyReplace($0, pattern: pattern, template: template) }
        }

        output = output.map { interpolate($0, in: node) }
        return output.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    /// 取单个字符串
    static func string(_ rule: String, in node: RuleNode, base: String) -> String? {
        guard rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
        return strings(rule, in: node, base: base).first
    }

    // MARK: - 求值

    private static func evaluate(_ part: Part, in node: RuleNode, base: String) -> [String] {
        // 纯模板规则：第{{$.order}}章 {{$.name}} / {$.chapterid} | {$.chapter} / https://…/{{$.id}}，直接拿当前 JSON 节点插值
        if part.path.contains("{{") || part.path.contains("{$.") {
            if case .json(let any) = node {
                return [interpolate(part.path, root: any)]
            }
        }

        var current: [Any] = []

        switch part.kind {
        case .css:
            guard case .html(let root) = node else { return [] }
            guard let elements = try? root.select(part.path) else { return [] }
            current = elements.array()

        case .json:
            guard case .json(let any) = node else { return [] }
            current = jsonValues(path: part.path, root: any)

        case .regex:
            let source = plainString(of: node) ?? ""
            return regexMatches(part.path, in: source)

        case .js:
            let source = plainString(of: node) ?? ""
            if let out = JSBridge.evaluate(script: part.path, result: source, baseUrl: base) {
                return [out]
            }
            return []

        case .xpath, .unsupported:
            return []
        }

        for step in part.steps {
            switch step {
            case .descend(let kind, let sub):
                var next: [Any] = []
                for item in current {
                    guard let element = item as? Element else { continue }
                    guard kind == .css else { continue }
                    if let elements = try? element.select(sub) {
                        next.append(contentsOf: elements.array())
                    }
                }
                current = next

            case .text:
                return current.compactMap { textValue(of: $0) }

            case .html:
                return current.compactMap { htmlValue(of: $0) }

            case .href:
                return current.compactMap { hrefValue(of: $0, attribute: "href", base: base) }

            case .src:
                return current.compactMap { hrefValue(of: $0, attribute: "src", base: base) }

            case .attr(let name):
                return current.compactMap { hrefValue(of: $0, attribute: name, base: base) }

            case .index(let n):
                let idx = n == -1 ? current.count - 1 : n
                guard idx >= 0, idx < current.count else { return [] }
                current = [current[idx]]
            }
        }

        // 没有取值步骤：默认当文本
        return current.compactMap { textValue(of: $0) }
    }

    private static func textValue(of item: Any) -> String? {
        if let element = item as? Element {
            let html = (try? element.outerHtml()) ?? ((try? element.html()) ?? "")
            return plainText(html: html)
        }
        return jsonString(item)
    }

    private static func htmlValue(of item: Any) -> String? {
        if let element = item as? Element { return (try? element.outerHtml()) ?? "" }
        return jsonString(item)
    }

    private static func hrefValue(of item: Any, attribute: String, base: String) -> String? {
        if let element = item as? Element {
            return absolutize((try? element.attr(attribute)) ?? "", base: base)
        }
        if let text = jsonString(item) { return absolutize(text, base: base) }
        return nil
    }

    // MARK: - ## 替换

    private static func applyReplace(_ text: String, pattern: String, template: String) -> String {
        guard pattern.isEmpty == false else { return text }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    // MARK: - 规则解析

    private static func parse(_ raw: String) -> Spec {
        var spec = Spec()
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty == false else { return spec }

        // Legado 的 ## 正则替换：rule##pattern##replacement##pattern2##replacement2
        if body.contains("##") {
            var pieces = body.components(separatedBy: "##")
            body = pieces.removeFirst()
            while pieces.isEmpty == false {
                let pattern = pieces.removeFirst()
                if pieces.isEmpty {
                    spec.replacements.append((pattern, ""))
                } else {
                    spec.replacements.append((pattern, pieces.removeFirst()))
                }
            }
        }

        // Legado 的 || 备用：前一条取不到再用后一条
        let alternatives = body.components(separatedBy: "||")
        for alternative in alternatives {
            if let part = parsePart(alternative, unsupported: &spec.unsupported) {
                spec.parts.append(part)
            }
        }
        return spec
    }

    /// 抽出 <js>...</js> 或 @js: 后面的脚本；不是 JS 规则返回 nil
    private static func extractJs(_ body: String) -> String? {
        if body.hasPrefix("@js:") {
            return String(body.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let regex = try? NSRegularExpression(pattern: "(?is)<js>(.*?)</js>") else { return nil }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: body, range: range), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parsePart(_ raw: String, unsupported: inout String?) -> Part? {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty == false else { return nil }

        if let script = Self.extractJs(body) {
            if JSBridge.needsHostBinding(script) {
                unsupported = "JS 规则用到了 java.ajax / org.jsoup 等宿主绑定，本机没实现"
                return nil
            }
            return Part(kind: .js, path: script, steps: [])
        }

        var kind: Kind = .css

        // Legado 的排除写法：-id:xxx / -class:xxx / -tag:xxx 开头，等于「先去掉这个元素，再从整篇里选」
        // 去掉一个容器对列表选择没有实质影响，这里直接改成「全局选 @ 后面的那段」
        if body.hasPrefix("-id:") || body.hasPrefix("-class:") || body.hasPrefix("-tag:") {
            guard let at = body.firstIndex(of: "@") else { return nil }
            body = String(body[body.index(after: at)...])
            if body.hasPrefix("tag.") {
                body = String(body.dropFirst(4))
                kind = .css
            } else if body.hasPrefix("class.") {
                body = "." + String(body.dropFirst(6))
                kind = .css
            } else if body.hasPrefix("id.") {
                body = "#" + String(body.dropFirst(3))
                kind = .css
            }
        }

        if body.hasPrefix("@css:") {
            body = String(body.dropFirst(5))
            kind = .css
        } else if body.hasPrefix("@XPath:") {
            body = String(body.dropFirst(7))
            kind = .xpath
        } else if body.hasPrefix("@xpath:") {
            body = String(body.dropFirst(7))
            kind = .xpath
        } else if body.lowercased().hasPrefix("@json:") {
            body = String(body.dropFirst(6))
            kind = .json
        } else if body.hasPrefix("class.") {
            body = "." + String(body.dropFirst(6))
            kind = .css
        } else if body.hasPrefix("id.") {
            body = "#" + String(body.dropFirst(3))
            kind = .css
        } else if body.hasPrefix("tag.") {
            body = String(body.dropFirst(4))
            kind = .css
        } else if body.hasPrefix("json:") {
            body = String(body.dropFirst(5))
            kind = .json
        } else if body.hasPrefix("regex:") {
            body = String(body.dropFirst(6))
            kind = .regex
        } else if body.hasPrefix("css:") {
            body = String(body.dropFirst(4))
            kind = .css
        } else if body.hasPrefix("$.") || body.hasPrefix("$[") {
            body = String(body.dropFirst(1))
            kind = .json
        } else if body.hasPrefix("//") || body.hasPrefix("/") || body.hasPrefix("(/") {
            kind = .xpath
            if body.hasPrefix("(/") {
                body = String(body.dropFirst(1))
            }
        }

        // 省略 $. 前缀的 JSON 路径：带 [*]/[0] 下标，或 data./Data./result. 开头的点号路径
        if kind == .css {
            let hasIndex = body.range(of: "\\[\\d+\\]|\\[\\*\\]", options: .regularExpression) != nil
            let bareRoot = body.range(of: "^(data|Data|result|Result)\\.[A-Za-z0-9_]", options: .regularExpression) != nil
            if hasIndex || (bareRoot && !body.contains(" ") && !body.contains("#") && !body.contains("@")) {
                kind = .json
            }
        }

        // 从右往左剥取值步骤
        var steps: [Step] = []
        // Legado 的 tag.p.1 / td.2 / a.0：标签或类名后面跟 .数字 = 取第 N 个
        if let dot = body.range(of: "\\.(\\d+)$", options: .regularExpression) {
            let n = Int(body[dot].dropFirst()) ?? 0
            body = String(body[body.startIndex..<dot.lowerBound])
            steps.append(.index(n))
        }
        while true {
            // Legado 的 !N 下标（tag.h2!0@text / class.list@tag.li!0），按位置落进步骤里
            if let found = body.range(of: "!\\d+$", options: .regularExpression) {
                let n = Int(body[found].dropFirst()) ?? 0
                steps.append(.index(n))
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            if let found = body.range(of: "@(text|textNodes|html|content|href|src)$", options: .regularExpression) {
                let token = String(body[found]).dropFirst()
                switch token {
                case "text", "textNodes": steps.append(.text)
                case "html", "content": steps.append(.html)
                case "href": steps.append(.href)
                default: steps.append(.src)
                }
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            if let found = body.range(of: "@tag\\.[A-Za-z0-9_-]+$", options: .regularExpression) {
                let tag = String(String(body[found]).dropFirst(5))
                steps.append(.descend(.css, tag))
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            if let found = body.range(of: "@css:[^@]+$", options: .regularExpression) {
                let selector = String(String(body[found]).dropFirst(5))
                steps.append(.descend(.css, selector))
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            if let found = body.range(of: "@attr\\([^)]*\\)$", options: .regularExpression) {
                let token = String(String(body[found]).dropFirst(6).dropLast())
                steps.append(.attr(token.trimmingCharacters(in: .whitespaces)))
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            // Legado 常见：@title / @data-title 这类属性名
            if let found = body.range(of: "@[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) {
                let name = String(body[found].dropFirst())
                if ["text", "textNodes", "html", "content", "href", "src"].contains(name) == false {
                    steps.append(.attr(name))
                    body = String(body[body.startIndex..<found.lowerBound])
                    continue
                }
            }
            // Legado 常见：@data-src 这类带连字符的属性名
            if let found = body.range(of: "@[A-Za-z][A-Za-z0-9_]*-[A-Za-z0-9_-]*$", options: .regularExpression) {
                let name = String(String(body[found]).dropFirst())
                steps.append(.attr(name))
                body = String(body[body.startIndex..<found.lowerBound])
                continue
            }
            break
        }
        steps.reverse()

        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty && steps.isEmpty { return nil }

        if kind == .xpath {
            if let converted = xpathToCSS(body) {
                return Part(kind: .css, path: converted.css, steps: converted.steps + steps)
            }
            unsupported = "XPath 写法太复杂，转换不了：\(raw)"
            return nil
        }

        return Part(kind: kind, path: body, steps: steps)
    }

    // MARK: - XPath → CSS（覆盖书源里最常见的写法）

    private static func xpathToCSS(_ xpath: String) -> (css: String, steps: [Step])? {
        var text = xpath.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("/") { text.removeFirst() }
        if text.isEmpty { return nil }

        let banned = ["following-sibling", "preceding-sibling", "ancestor", "parent::",
                      "not(", "starts-with", "normalize-space", "contains(text()",
                      "position()", "last()", " and ", " or ", "|"]
        for item in banned where text.contains(item) { return nil }

        var tokens: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            if character == "[" { depth += 1 }
            if character == "]" { depth -= 1 }
            if character == "/" && depth == 0 {
                tokens.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        tokens.append(current)

        var cssParts: [String] = []
        var steps: [Step] = []

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "." || trimmed == "*" { continue }
            if trimmed == ".." { return nil }
            if trimmed == "text()" || trimmed == "string()" {
                steps.append(.text)
                continue
            }
            // //a/@href 这种属性轴
            if trimmed.hasPrefix("@"), let attribute = trimmed.dropFirst().split(separator: "[").first {
                steps.append(.attr(String(attribute)))
                continue
            }
            if trimmed.hasPrefix("descendant::") {
                let rest = String(trimmed.dropFirst(12))
                if let css = segmentToCSS(rest) { cssParts.append(css) }
                continue
            }
            guard let css = segmentToCSS(trimmed) else { return nil }
            cssParts.append(css)
        }

        guard cssParts.isEmpty == false else { return nil }
        return (cssParts.joined(separator: " "), steps)
    }

    private static func segmentToCSS(_ segment: String) -> String? {
        var tag = "*"
        var predicates: [String] = []

        if let bracket = segment.firstIndex(of: "[") {
            tag = String(segment[segment.startIndex..<bracket])
            var rest = String(segment[bracket...])
            while let open = rest.firstIndex(of: "[") {
                guard let close = rest[open...].firstIndex(of: "]") else { return nil }
                let inside = String(rest[rest.index(after: open)..<close])
                predicates.append(inside)
                rest = String(rest[rest.index(after: close)...])
            }
        } else {
            tag = segment
        }

        tag = tag.trimmingCharacters(in: .whitespaces)
        if tag.isEmpty { tag = "*" }

        var css = tag

        for predicate in predicates {
            let item = predicate.trimmingCharacters(in: .whitespaces)

            if item.hasPrefix("contains("), item.hasSuffix(")") {
                let inner = item.dropFirst(9).dropLast()
                let pieces = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { return nil }
                let name = String(pieces[0])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: "")
                let value = String(pieces[1])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                switch name {
                case "class":
                    for token in value.split(separator: " ") { css += "." + token }
                case "id":
                    css += "[id*=\"\(value)\"]"
                default:
                    css += "[\(name)*=\"\(value)\"]"
                }
                continue
            }

            if item.hasPrefix("@") {
                let after = String(item.dropFirst())
                if let equal = after.firstIndex(of: "=") {
                    let name = String(after[after.startIndex..<equal])
                    let value = String(after[after.index(after: equal)...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    switch name {
                    case "id":
                        css += "#" + value
                    case "class":
                        for token in value.split(separator: " ") { css += "." + token }
                    default:
                        css += "[\(name)=\"\(value)\"]"
                    }
                } else {
                    css += "[\(after)]"
                }
                continue
            }

            if let index = Int(item) {
                css += ":nth-child(\(index))"
                continue
            }

            return nil
        }

        if css == "*" { css = "" }
        return css
    }

    // MARK: - HTML → 文本

    /// 用系统 HTML 解析器转纯文本，段落结构保留得比手写剥离更准
    static func plainText(html: String) -> String {
        guard html.isEmpty == false else { return "" }
        let wrapped = "<meta charset=\"utf-8\">" + html

        if let data = wrapped.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return normalize(attributed.string)
            }
        }
        return normalize(stripTags(html))
    }

    private static func stripTags(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr|section|blockquote)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text
    }

    static func normalize(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")

        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if lines.last?.isEmpty == false { lines.append("") }
            } else {
                lines.append(trimmed)
            }
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        text = lines.joined(separator: "\n")
        return text
    }

    // MARK: - 地址

    static func absolutize(_ path: String, base: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }

        if trimmed.hasPrefix("//") {
            if let scheme = URL(string: base)?.scheme { return "\(scheme):\(trimmed)" }
            return "https:" + trimmed
        }

        if let baseURL = URL(string: base),
           let resolved = URL(string: trimmed, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return trimmed
    }

    // MARK: - JSON

    private static func segments(_ path: String) -> [String] {
        var result: [String] = []
        for part in path.split(separator: ".", omittingEmptySubsequences: true) {
            var token = String(part)
            while let open = token.lastIndex(of: "["), token.hasSuffix("]") {
                let inside = token[token.index(after: open)..<token.index(before: token.endIndex)]
                result.append("[\(inside)]")
                token = String(token[token.startIndex..<open])
            }
            if token.isEmpty == false { result.append(token) }
        }
        return result
    }

    private static func jsonValues(path: String, root: Any) -> [Any] {
        var chain: [(isIndex: Bool, value: String)] = []
        for segment in segments(path) {
            if segment.hasPrefix("[") {
                chain.append((true, String(segment.dropFirst().dropLast())))
            } else {
                chain.append((false, segment))
            }
        }

        var current: [Any] = [root]
        for (isIndex, token) in chain {
            var next: [Any] = []
            for item in current {
                if isIndex {
                    if token == "*" {
                        if let array = item as? [Any] { next.append(contentsOf: array) }
                    } else if let index = Int(token), index >= 0, let array = item as? [Any], index < array.count {
                        next.append(array[index])
                    }
                } else if let dict = item as? [String: Any], let value = dict[token] {
                    next.append(value)
                }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
    }

    private static func jsonString(_ value: Any) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// 把结果里残留的 {{$.field}} 模板，按当前 JSON 节点填上
    private static func interpolate(_ text: String, in node: RuleNode) -> String {
        guard text.contains("{{") else { return text }
        guard case .json(let any) = node else { return text }
        return interpolate(text, root: any)
    }

    private static func interpolate(_ text: String, root: Any) -> String {
        guard text.contains("{{") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{?\\s*\\$\\.([A-Za-z0-9_.\\[\\]]*)\\s*\\}?\\}") else { return text }
        var out = text
        let ns = out as NSString
        let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let path = ns.substring(with: match.range(at: 1))
            let value = jsonValues(path: path, root: root).compactMap(jsonString).first ?? ""
            if let range = Range(match.range, in: out) {
                out.replaceSubrange(range, with: value)
            }
        }
        return out
    }

    private static func plainString(of node: RuleNode) -> String? {
        switch node {
        case .html(let element):
            let html = (try? element.outerHtml()) ?? ""
            return plainText(html: html)
        case .json(let any):
            return jsonString(any)
        }
    }

    // MARK: - 正则

    static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard pattern.isEmpty == false, text.isEmpty == false else { return [] }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var results: [String] = []
        for match in regex.matches(in: text, range: range) {
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                results.append(ns.substring(with: match.range(at: 1)))
            } else if match.range.location != NSNotFound {
                results.append(ns.substring(with: match.range))
            }
        }
        return results
    }
}
