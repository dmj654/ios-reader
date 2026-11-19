//
//  TextPaginator.swift
//  ReaderApp
//
//  用 CoreText 把整本书切成一页一页。
//  好处：iOS 原生排版引擎，结果精确，且不需要自己算行高。
//

import UIKit
import CoreText

enum TextPaginator {

    /// 构造正文排版属性
    static func attributes(fontSize: CGFloat, lineSpacing: CGFloat, color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = lineSpacing * 0.6
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: UIFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraph,
            .foregroundColor: color,
            .kern: 0.0
        ]
    }

    /// 把全文分页，返回每页在全文中的 NSRange
    static func paginate(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        pageSize: CGSize
    ) -> [NSRange] {
        guard text.isEmpty == false else { return [NSRange(location: 0, length: 0)] }
        guard pageSize.width > 10, pageSize.height > 10 else { return [NSRange(location: 0, length: text.utf16.count)] }

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)

        var ranges: [NSRange] = []
        var start = 0
        let total = attributed.length

        while start < total {
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(start, 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            ranges.append(NSRange(location: start, length: visible.length))
            start += visible.length
        }

        if ranges.isEmpty {
            ranges = [NSRange(location: 0, length: total)]
        }
        return ranges
    }

    /// 找到包含指定偏移的页码
    static func pageIndex(for offset: Int, in ranges: [NSRange]) -> Int {
        guard ranges.isEmpty == false else { return 0 }
        for (index, range) in ranges.enumerated() {
            if offset < range.location + range.length {
                return index
            }
        }
        return ranges.count - 1
    }
}
