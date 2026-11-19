//
//  RuleParser.swift
//  ReaderApp
//
//  规则解析器：把书源里的一行规则，跑成文本 / 链接 / 节点列表
//
//  规则写法：
//    css:选择器                 取元素（可加后缀取值）
//    json:路径                  取 JSON 字段，支持 a.b[0].c
//    regex:正则                 在文本里抓匹配
//  取值后缀（写在行尾）：
//    @text        元素里的纯文本（保留段落换行）
//    @html        元素原始 HTML
//    @href        元素 href，自动补全成绝对地址
//    @src         元素 src，自动补全成绝对地址
//    @attr(名字)  元素任意属性
//

import Foundation
import SwiftSoup

indirect enum RuleNode {
    case html(Element)
    case json(Any)
}

enum RuleParser {

    private enum Kind {
        case css, json, regex
    }

    private enum Suffix {
        case text, html, href, src, attr(String)
    }

    private struct Spec {
        var kind: Kind
        var path: String
        var suffix: Suffix?
    }

    // MARK: - 对外

    static func parseHTML(_ html: String) -> RuleNode? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        return .html(document)
    }

    /// 取一组节点（结果列表用）
    static func nodes(_ rule: String, in node: RuleNode, base: String) -> [RuleNode] {
        let spec = parse(rule)
        switch spec.kind {
        case .css:
            guard case .html(let root) = node else { return [] }
            guard let elements = try? root.select(spec.path) else { return [] }
            return elements.array().map { RuleNode.html($0) }

        case .json:
            guard case .json(let any) = node else { return [] }
            var output: [RuleNode] = []
            for value in jsonValues(path: spec.path, root: any) {
                if let array = value as? [Any] {
                    output.append(contentsOf: array.map { RuleNode.json($0) })
                } else {
                    output.append(.json(value))
                }
            }
            return output

        case .regex:
            return []
        }
    }

    /// 取一组字符串（图片列表用）
    static func strings(_ rule: String, in node: RuleNode, base: String) -> [String] {
        let spec = parse(rule)

        if spec.kind == .regex {
            let source = plainString(of: node) ?? ""
            let matches = regexMatches(spec.path, in: source)
            if spec.suffix == nil { return matches.first.map { [$0] } ?? [] }
            return matches
        }

        let resolved = nodes(rule, in: node, base: base)
        return resolved
            .compactMap { value(of: $0, suffix: spec.suffix, base: base) }
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    /// 取单个字符串
    static func string(_ rule: String, in node: RuleNode, base: String) -> String? {
        guard rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
        return strings(rule, in: node, base: base).first
    }

    // MARK: - 取值

    private static func value(of node: RuleNode, suffix: Suffix?, base: String) -> String? {
        switch node {
        case .html(let element):
            switch suffix {
            case .none, .text:
                let html = (try? element.outerHtml()) ?? (try? element.html()) ?? ""
                return plainText(html: html)
            case .html:
                return (try? element.outerHtml()) ?? ""
            case .href:
                return absolutize(element.attr("href"), base: base)
            case .src:
                return absolutize(element.attr("src"), base: base)
            case .attr(let name):
                return element.attr(name)
            }

        case .json(let any):
            guard let text = jsonString(any) else { return nil }
            switch suffix {
            case .href, .src:
                return absolutize(text, base: base)
            default:
                return text
            }
        }
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

    private enum Segment {
        case key(String)
        case index(Int)
    }

    private static func segments(_ path: String) -> [Segment] {
        var result: [Segment] = []
        for part in path.split(separator: ".", omittingEmptySubsequences: true) {
            var token = String(part)
            while let open = token.lastIndex(of: "["), token.hasSuffix("]") {
                let inside = token[token.index(after: open)..<token.index(before: token.endIndex)]
                if let index = Int(inside) { result.append(.index(index)) }
                token = String(token[token.startIndex..<open])
            }
            if token.isEmpty == false { result.append(.key(token)) }
        }
        return result
    }

    private static func jsonValues(path: String, root: Any) -> [Any] {
        var current: [Any] = [root]
        for segment in segments(path) {
            var next: [Any] = []
            for item in current {
                switch segment {
                case .key(let key):
                    if let dict = item as? [String: Any], let value = dict[key] {
                        next.append(value)
                    }
                case .index(let index):
                    if let array = item as? [Any], index >= 0, index < array.count {
                        next.append(array[index])
                    }
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

    // MARK: - 解析规则头

    private static func parse(_ rule: String) -> Spec {
        var body = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        var suffix: Suffix?

        if let found = body.range(of: "@(text|html|href|src|attr\\([^)]*\\))$", options: .regularExpression) {
            let token = String(body[found]).dropFirst()
            switch token {
            case "text": suffix = .text
            case "html": suffix = .html
            case "href": suffix = .href
            case "src": suffix = .src
            default:
                if token.hasPrefix("attr(") {
                    let inner = token.dropFirst(5).dropLast()
                    suffix = .attr(String(inner).trimmingCharacters(in: .whitespaces))
                }
            }
            body = String(body[body.startIndex..<found.lowerBound])
        }

        if body.hasPrefix("json:") {
            return Spec(kind: .json, path: String(body.dropFirst(5)), suffix: suffix)
        }
        if body.hasPrefix("regex:") {
            return Spec(kind: .regex, path: String(body.dropFirst(6)), suffix: suffix)
        }
        if body.hasPrefix("css:") {
            return Spec(kind: .css, path: String(body.dropFirst(4)), suffix: suffix)
        }
        return Spec(kind: .css, path: body, suffix: suffix)
    }
}
