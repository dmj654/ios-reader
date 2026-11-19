//
//  BookText.swift
//  ReaderApp
//
//  统一文本内容模型：TXT / EPUB 解析后都变成「章节列表」
//

import Foundation

struct Chapter: Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var text: String
}

struct BookText {
    var title: String
    var author: String
    var chapters: [Chapter]

    /// 合并为全文，并记录每章在全文中的起始位置（UTF-16 偏移）
    func flattened() -> (text: String, chapterStarts: [Int]) {
        let result = NSMutableString()
        var starts: [Int] = []
        for chapter in chapters {
            starts.append(result.length)
            result.append(chapter.title)
            result.append("\n\n")
            result.append(chapter.text)
            result.append("\n\n")
        }
        return (result as String, starts)
    }

    /// 全文总长度（UTF-16），用于进度计算
    var totalLength: Int {
        flattened().text.utf16.count
    }
}
