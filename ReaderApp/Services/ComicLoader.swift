//
//  ComicLoader.swift
//  ReaderApp
//
//  CBZ / ZIP 漫画：列出图片条目，按页码顺序排序，按需解压单页
//

import Foundation
import UIKit
import ZIPFoundation

enum ComicLoader {

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    /// 返回压缩包内所有图片的路径（已按自然顺序排好）
    static func listPages(url: URL) -> [String] {
        guard let archive = Archive(url: url, accessMode: .read) else { return [] }
        var paths: [String] = []
        for entry in archive {
            if entry.type == .directory { continue }
            let ext = (entry.path as NSString).pathExtension.lowercased()
            if imageExts.contains(ext) {
                paths.append(entry.path)
            }
        }
        // 屏蔽 macOS 压缩时产生的垃圾条目
        paths.removeAll { $0.contains("__MACOSX") || $0.hasPrefix(".") }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 解出一页图片
    static func image(at path: String, in url: URL) -> UIImage? {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = archive[path] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }
        return UIImage(data: data)
    }
}
