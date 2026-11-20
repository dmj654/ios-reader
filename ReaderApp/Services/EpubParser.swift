//
//  EpubParser.swift
//  ReaderApp
//
//  EPUB 解析：解压 → 读 container.xml → 读 opf → 按 spine 顺序取每章正文
//

import Foundation
import UIKit
import ImageIO
import ZIPFoundation

enum EpubParser {

    /// imageDir 不为空时，把章节里的插图解出来存进去，并记录每张图在章内的位置
    static func load(url: URL, imageDir: URL? = nil) -> BookText? {
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
        var imageCounter = 0

        if let imageDir {
            try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        }

        for ref in opf.spine {
            guard let meta = opf.manifest[ref] else { continue }
            // 只看文字内容，字体等跳过
            let type = meta.mediaType
            guard type.contains("html") || type.contains("xml") else { continue }

            let entryPath = resolve(path: meta.href, base: opfDir)
            guard let data = read(entryPath: entryPath, from: archive) else { continue }

            let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            guard raw.isEmpty == false else { continue }

            let title = extractTitle(html: raw) ?? "第 \(chapters.count + 1) 节"
            let htmlDir = (entryPath as NSString).deletingLastPathComponent

            let parsed = htmlToTextWithImages(
                raw,
                archive: archive,
                baseDir: htmlDir,
                imageDir: imageDir,
                nextIndex: &imageCounter
            )

            let plain = parsed.text
            guard plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || parsed.images.isEmpty == false else { continue }

            chapters.append(Chapter(title: title, text: plain, images: parsed.images))
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

    // MARK: - HTML → 文本 + 插图

    private static let marker = "\u{FFFC}"

    /// 把 <img> 换成占位符 → 文本化 → 按顺序把图存盘，记录章内偏移
    private static func htmlToTextWithImages(
        _ html: String,
        archive: Archive,
        baseDir: String,
        imageDir: URL?,
        nextIndex: inout Int
    ) -> (text: String, images: [ChapterImage]) {

        var srcs: [String] = []
        var marked = html

        if let regex = try? NSRegularExpression(pattern: "(?is)<img[^>]*src\\s*=\\s*(\"[^\"]*\"|'[^']*')[^>]*>") {
            let ns = html as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: html, range: range) where match.numberOfRanges > 1 {
                let raw = ns.substring(with: match.range(at: 1))
                let cleaned = raw
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty == false { srcs.append(cleaned) }
            }
            marked = regex.stringByReplacingMatches(in: html, range: range, withTemplate: marker)
        }

        var plain = htmlToPlainText(marked)

        guard plain.contains(marker), let imageDir, srcs.isEmpty == false else {
            plain = plain.replacingOccurrences(of: marker, with: "")
            return (plain, [])
        }

        var output = ""
        var outputLength = 0          // 已写入文本的 UTF-16 长度
        var imageCursor = 0
        var images: [ChapterImage] = []

        for character in plain {
            if character == "\u{FFFC}" {
                let index = imageCursor
                imageCursor += 1
                guard index < srcs.count else { continue }

                let entryPath = resolve(path: srcs[index], base: baseDir)
                guard let data = read(entryPath: entryPath, from: archive),
                      let size = pixelSize(of: data) else { continue }

                // 过滤装饰性小图 / 长条 banner，避免正文里插进一堆没内容的整页
                let longSide = max(size.width, size.height)
                let shortSide = min(size.width, size.height)
                guard longSide >= 320 else { continue }
                guard shortSide > 1, longSide / shortSide <= 4 else { continue }

                nextIndex += 1
                let fileName = String(format: "img_%04d.jpg", nextIndex)
                let target = imageDir.appendingPathComponent(fileName)
                guard saveImage(data: data, to: target) else { continue }

                images.append(ChapterImage(offset: outputLength, file: fileName))
                continue
            }

            output.append(character)
            outputLength += String(character).utf16.count
        }

        return (output, images)
    }

    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: width, height: height)
    }

    /// 统一转 JPEG 落盘，超大的图先缩到 2400 以内
    private static func saveImage(data: Data, to url: URL) -> Bool {
        guard let source = UIImage(data: data) else { return false }

        var image = source
        let maxPixel: CGFloat = 2400
        if max(source.size.width, source.size.height) > maxPixel {
            let scale = maxPixel / max(source.size.width, source.size.height)
            let target = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: target)
            image = renderer.image { _ in
                source.draw(in: CGRect(origin: .zero, size: target))
            }
        }

        if let jpeg = image.jpegData(compressionQuality: 0.85) {
            return (try? jpeg.write(to: url, options: .atomic)) != nil
        }
        return (try? data.write(to: url, options: .atomic)) != nil
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
