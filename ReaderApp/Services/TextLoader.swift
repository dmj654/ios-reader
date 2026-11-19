//
//  TextLoader.swift
//  ReaderApp
//
//  TXT 读取：自动识别编码 + 智能分章
//

import Foundation

enum TextLoader {

    /// 依次尝试常见中文编码
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: big5)) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if let s = String(data: data, encoding: .gbk_95_plain) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    /// 读取 TXT
    static func load(url: URL, fallbackTitle: String) -> BookText {
        guard let data = try? Data(contentsOf: url),
              var content = decode(data) else {
            return BookText(title: fallbackTitle, author: "未知", chapters: [
                Chapter(title: "无法读取", text: "文件读取失败，可能是编码不支持或文件损坏。")
            ])
        }

        content = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // 去掉 BOM
        content = content.replacingOccurrences(of: "\u{FEFF}", with: "")

        let chapters = splitIntoChapters(content)
        return BookText(title: fallbackTitle, author: "未知", chapters: chapters)
    }

    /// 章节标题的正则
    private static let chapterPattern = try! NSRegularExpression(
        pattern: "^(?:(?:正文)?\\s*)?(第[0-9零〇一二三四五六七八九十百千万两]{1,10}[章节回卷部篇集幕]|序章|序言|楔子|引子|前言|后记|尾声|终章|番外|Chapter\\s+\\d+|CHAPTER\\s+\\d+).{0,30}$",
        options: []
    )

    /// 按行切分章节
    static func splitIntoChapters(_ content: String) -> [Chapter] {
        let lines = content.components(separatedBy: "\n")
        var chapters: [Chapter] = []

        var currentTitle: String? = nil
        var buffer: [String] = []

        func flush() {
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.isEmpty == false else { return }
            chapters.append(Chapter(title: currentTitle ?? "正文", text: body))
            buffer.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if buffer.isEmpty == false { buffer.append("") }
                continue
            }
            if isChapterTitle(trimmed) {
                flush()
                currentTitle = trimmed
            } else {
                buffer.append(trimmed)
            }
        }
        flush()

        if chapters.isEmpty {
            let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
            chapters = [Chapter(title: "正文", text: body)]
        }
        return chapters
    }

    private static func isChapterTitle(_ line: String) -> Bool {
        guard line.count <= 40 else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return chapterPattern.firstMatch(in: line, options: [], range: range) != nil
    }
}

// MARK: - 补充编码支持

extension String.Encoding {
    static var gbk_95_plain: String.Encoding {
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))
        return String.Encoding(rawValue: enc)
    }
}
