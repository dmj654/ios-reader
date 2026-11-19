//
//  CoverStore.swift
//  ReaderApp
//
//  书架封面：从书籍本体抽出第一页做封面，落盘缓存，书架直接读图
//  - CBZ 漫画 → 压缩包第一张图
//  - PDF → 第 1 页渲染
//  - EPUB → 包里名字带 cover 的图（没有就取第一张图）
//  - TXT → 没有封面，书架用首字色块占位
//

import Foundation
import UIKit
import ImageIO
import PDFKit
import ZIPFoundation

enum CoverStore {

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp"]

    private static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Covers", isDirectory: true)
    }

    private static func ensureDir() {
        if FileManager.default.fileExists(atPath: dir.path) == false {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private static func fileURL(for id: UUID) -> URL {
        dir.appendingPathComponent("cover-\(id.uuidString).jpg")
    }

    /// 已经生成过就直接给，书架首屏用它，不再重新解包
    static func cached(bookID: UUID) -> UIImage? {
        let url = fileURL(for: bookID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func clear(bookID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: bookID))
    }

    /// 生成并落盘（耗时操作，务必在后台线程调用）
    @discardableResult
    static func generate(url: URL, format: BookFormat, bookID: UUID) -> UIImage? {
        if let hit = cached(bookID: bookID) { return hit }
        guard let image = render(url: url, format: format) else { return nil }
        ensureDir()
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: fileURL(for: bookID), options: .atomic)
        }
        return image
    }

    // MARK: - 各格式取封面

    private static func render(url: URL, format: BookFormat) -> UIImage? {
        switch format {
        case .comic:
            let pages = ComicLoader.listPages(url: url)
            guard let first = pages.first else { return nil }
            return ComicLoader.thumbnail(at: first, in: url, maxPixel: 900)
        case .pdf:
            return pdfCover(url: url)
        case .epub:
            return epubCover(url: url)
        case .txt:
            return nil
        }
    }

    private static func pdfCover(url: URL) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let width: CGFloat = 900
        let height = max(1, width * bounds.height / bounds.width)
        return page.thumbnail(of: CGSize(width: width, height: height), for: .cropBox)
    }

    private static func epubCover(url: URL) -> UIImage? {
        guard let archive = Archive(url: url, accessMode: .read) else { return nil }

        var candidates: [String] = []
        for entry in archive {
            if entry.type == .directory { continue }
            if entry.path.contains("__MACOSX") || entry.path.hasPrefix(".") { continue }
            let ext = (entry.path as NSString).pathExtension.lowercased()
            if imageExts.contains(ext) { candidates.append(entry.path) }
        }
        guard candidates.isEmpty == false else { return nil }

        let sorted = candidates.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let name = candidates.first { $0.lowercased().contains("cover") } ?? sorted[0]
        guard let entry = archive[name] else { return nil }

        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in data.append(chunk) }
        } catch {
            return nil
        }
        return decode(data, maxPixel: 900)
    }

    private static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}
