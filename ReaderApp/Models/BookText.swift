//
//  BookText.swift
//  ReaderApp
//
//  统一文本内容模型：TXT / EPUB 解析后都变成「章节列表」
//  EPUB 的插图作为「章内图片」挂在章节上，带章内字符偏移
//

import Foundation
import CoreGraphics

/// 章内插图：offset 为 chapter.text 中的 UTF-16 偏移
struct ChapterImage: Codable, Hashable {
    var offset: Int
    var file: String
}

struct Chapter: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var text: String
    var images: [ChapterImage] = []
}

struct BookText: Codable {
    /// 全文里的图片锚点（offset 为全文 UTF-16 偏移）
    struct ImageAnchor: Hashable {
        var offset: Int
        var file: String
    }

    var title: String
    var author: String
    var chapters: [Chapter]

    /// 合并为全文，并记录每章起始位置与所有图片锚点（均已排序）
    func flattened() -> (text: String, chapterStarts: [Int], imageAnchors: [ImageAnchor]) {
        let result = NSMutableString()
        var starts: [Int] = []
        var anchors: [ImageAnchor] = []

        for chapter in chapters {
            starts.append(result.length)
            result.append(chapter.title)
            result.append("\n\n")

            let textStart = result.length
            result.append(chapter.text)
            let textLength = chapter.text.utf16.count
            for image in chapter.images {
                let clamped = min(max(0, image.offset), textLength)
                anchors.append(ImageAnchor(offset: textStart + clamped, file: image.file))
            }

            result.append("\n\n")
        }

        anchors.sort { $0.offset < $1.offset }
        return (result as String, starts, anchors)
    }

    /// 全文总长度（UTF-16），用于进度计算
    var totalLength: Int {
        flattened().text.utf16.count
    }
}
