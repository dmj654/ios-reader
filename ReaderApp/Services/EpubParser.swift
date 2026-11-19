//
//  EpubParser.swift
//  ReaderApp
//
//  EPUB 解析：解压 → 读 container.xml → 读 opf → 按 spine 顺序取每章正文
//

import Foundation
import ZIPFoundation

enum EpubParser {

    static func load(url: URL) -> BookText? {
        guard let archive = Archive(url: url, accessMode: .read) else { return nil }

        // 1. 读 container.xml，找到 opf 路径
        guard let opfPath = findOpfPath(in: archive) else { return nil }
        guard let opfData = read(entryPath: opfPath, from: archive) else { return nil }

        let opf = OpfParser()
        let parser = XMLParser(data: opfData)
        parser.delegate = opf
        parser.parse()

        // 2. 按 spine 顺序读每一章
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        var chapters: [Chapter] = []

        for ref in opf.spine {
            guard let meta = opf.manifest[ref] else { continue }
            // 只看文字内容，图片/字体跳过
            let type = meta.mediaType
            guard type.contains("html") || type.contains("xml") else { continue }

            let entryPath = resolve(path: meta.href, base: opfDir)
            guard let data = read(entryPath: entryPath, from: archive) else { continue }

            let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            let plain = htmlToPlainText(raw)
            guard plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }

            let title = extractTitle(html: raw) ?? "第 \(chapters.count + 1) 节"
            chapters.append(Chapter(title: title, text: plain))
        }

        guard chapters.isEmpty == false else { return nil }

        return BookText(
            title: opf.title.isEmpty ? url.deletingPathExtension().lastPathComponent : opf.title,
            author: opf.creator.isEmpty ? "未知" : opf.creator,
            chapters: chapters
        )
    }

    // MARK: - 工具

    private static func findOpfPath(in archive: Archive) -> String? {
        guard let data = read(entryPath: "META-INF/container.xml", from: archive) else { return nil }
        let container = ContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = container
        parser.parse()
        return container.rootFilePath
    }

    /// 从 ZIP 里读出一整个文件的字节
    static func read(entryPath: String, from archive: Archive) -> Data? {
        guard let entry = archive[entryPath] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }
        return data.isEmpty ? nil : data
    }

    /// 把 opf 里的相对路径补全成 zip 内的路径
    static func resolve(path: String, base: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") { return String(decoded.dropFirst()) }
        if base.isEmpty { return decoded }
        return (base as NSString).appendingPathComponent(decoded)
    }

    // MARK: - HTML → 纯文本

    static func htmlToPlainText(_ html: String) -> String {
        var text = html

        // 去掉 script / style
        text = text.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: "",
            options: .regularExpression
        )
        // 块级标签换成换行
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(p|div|h[1-6]|li|tr)>", with: "\n", options: .regularExpression)
        // 去掉所有标签
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)

        // 基本实体
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&hellip;": "…"
        ]
        for (k, v) in entities {
            text = text.replacingOccurrences(of: k, with: v)
        }

        // 压缩多余空行
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 html 里猜章节标题
    private static func extractTitle(html: String) -> String? {
        let patterns = ["(?is)<h1[^>]*>(.*?)</h1>", "(?is)<h2[^>]*>(.*?)</h2>"]
        for p in patterns {
            if let range = html.range(of: p, options: .regularExpression) {
                let raw = String(html[range])
                let plain = htmlToPlainText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if plain.isEmpty == false && plain.count <= 40 { return plain }
            }
        }
        return nil
    }
}

// MARK: - container.xml 解析

private final class ContainerParser: NSObject, XMLParserDelegate {
    var rootFilePath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile" {
            rootFilePath = attributeDict["full-path"]
        }
    }
}

// MARK: - opf 解析

private final class OpfParser: NSObject, XMLParserDelegate {

    struct Meta {
        var href: String
        var mediaType: String
    }

    var title = ""
    var creator = ""
    var manifest: [String: Meta] = [:]
    var spine: [String] = []

    private var currentElement = ""
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""

        switch elementName {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = Meta(href: href, mediaType: attributeDict["media-type"] ?? "")
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spine.append(idref)
            }
        case "spine":
            spine.removeAll()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title" || elementName == "dc:title" {
            if title.isEmpty { title = value }
        }
        if elementName == "creator" || elementName == "dc:creator" {
            if creator.isEmpty { creator = value }
        }
        buffer = ""
    }
}
