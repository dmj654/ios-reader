//
//  ComicLoader.swift
//  ReaderApp
//
//  CBZ / ZIP 漫画：列页、解压单页、内存缓存、缩略图
//

import Foundation
import UIKit
import ImageIO
import ZIPFoundation

enum ComicLoader {

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    /// 已解码页面的内存缓存（预读的页直接命中，翻页不再白屏）
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    private static func key(_ path: String, _ url: URL) -> NSString {
        "\(url.lastPathComponent)#\(path)" as NSString
    }

    static func cached(path: String, url: URL) -> Bool {
        cache.object(forKey: key(path, url)) != nil
    }

    static func cachedImage(at path: String, in url: URL) -> UIImage? {
        cache.object(forKey: key(path, url))
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

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
        paths.removeAll { $0.contains("__MACOSX") || $0.hasPrefix(".") }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 解出一页图片（带缓存）
    static func image(at path: String, in url: URL) -> UIImage? {
        let cacheKey = key(path, url)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard let image = decode(path: path, in: url) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func rawData(at path: String, in url: URL) -> Data? {
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
        return data.isEmpty ? nil : data
    }

    private static func decode(path: String, in url: URL) -> UIImage? {
        guard let data = rawData(at: path, in: url) else { return nil }
        return UIImage(data: data)
    }

    /// 缩略图（目录网格用，降采样以免撑爆内存）
    static func thumbnail(at path: String, in url: URL, maxPixel: CGFloat = 240) -> UIImage? {
        guard let data = rawData(at: path, in: url) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
