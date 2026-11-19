//
//  ComicLoader.swift
//  ReaderApp
//
//  CBZ / ZIP 漫画：列页、解压单页、内存缓存、缩略图、自动裁白边
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
        cache.countLimit = 12
        return cache
    }()

    private static func key(_ path: String, _ url: URL, trim: Bool) -> NSString {
        "\(url.lastPathComponent)#\(path)#\(trim ? "t" : "n")" as NSString
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

    /// 解出一页图片（带缓存；trim = 自动裁掉四周白边）
    static func image(at path: String, in url: URL, trim: Bool = false) -> UIImage? {
        let cacheKey = key(path, url, trim: trim)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard var image = decode(path: path, in: url) else { return nil }
        if trim { image = trimWhiteBorder(image) }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    static func cachedImage(at path: String, in url: URL, trim: Bool = false) -> UIImage? {
        cache.object(forKey: key(path, url, trim: trim))
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        // 超大页降采样到 2048 以内，避免内存爆掉
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? Double) ?? 0
        if max(pixelWidth, pixelHeight) <= 2048 {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 自动裁白边

    /// 上下左右的白边裁掉（每边最多裁 15%，识别不出就不裁）
    private static func trimWhiteBorder(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }

        let sampleW = 120
        let ratio = CGFloat(cg.height) / CGFloat(cg.width)
        let sampleH = max(1, Int((CGFloat(sampleW) * ratio).rounded()))

        let smallSize = CGSize(width: CGFloat(sampleW), height: CGFloat(sampleH))
        let renderer = UIGraphicsImageRenderer(size: smallSize)
        let small = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: smallSize))
        }
        guard let smallCG = small.cgImage,
              let cfData = smallCG.dataProvider?.data,
              let bytes = CFDataGetBytePtr(cfData) else { return image }

        let bytesPerRow = smallCG.bytesPerRow
        let bitsPerPixel = smallCG.bitsPerPixel
        guard bitsPerPixel >= 24 else { return image }

        var minX = sampleW, maxX = -1, minY = sampleH, maxY = -1
        for y in 0..<sampleH {
            for x in 0..<sampleW {
                let offset = y * bytesPerRow + x * bitsPerPixel / 8
                let r = Int(bytes[offset])
                let g = Int(bytes[offset + 1])
                let b = Int(bytes[offset + 2])
                let lum = (r * 30 + g * 59 + b * 11) / 100
                if lum < 236 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX > minX, maxY > minY else { return image }

        // 允许每边最多裁掉 15%
        let maxLeft = CGFloat(sampleW) * 0.15
        let maxTop = CGFloat(sampleH) * 0.15
        let forceZero: CGFloat = 0

        let left = min(CGFloat(minX), maxLeft)
        let right = min(CGFloat(sampleW - 1 - maxX), maxLeft)
        let top = min(CGFloat(minY), maxTop)
        let bottom = min(CGFloat(sampleH - 1 - maxY), maxTop)

        guard left > 1 || right > 1 || top > 1 || bottom > 1 else { return image }

        let sx = CGFloat(cg.width) / CGFloat(sampleW)
        let sy = CGFloat(cg.height) / CGFloat(sampleH)
        let rect = CGRect(
            x: max(forceZero, left * sx),
            y: max(forceZero, top * sy),
            width: CGFloat(cg.width) - (left + right) * sx,
            height: CGFloat(cg.height) - (top + bottom) * sy
        )
        guard rect.width > 64, rect.height > 64 else { return image }
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
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
