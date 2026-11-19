//
//  BookshelfViewModel.swift
//  ReaderApp
//
//  书架：导入 / 扫描本地文件 / 删除 / 进度保存
//  关键点：通过「文件」App 或数据线放进来的书会落在 Documents 根目录，
//         所以每次启动和回到前台都要扫描根目录 + Books 子目录，并把根目录的书归位。
//

import Foundation
import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class BookshelfViewModel: ObservableObject {

    @Published var books: [Book] = []
    @Published var alertMessage: String?

    private let fm = FileManager.default
    private let storeURL: URL
    private let shelfFileName = "bookshelf.json"

    /// App 沙盒的 Documents 目录（「文件」App 里显示为「我的 iPhone / 本地阅读器」）
    private var docsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 书籍统一存放目录
    var booksDir: URL {
        docsDir.appendingPathComponent("Books")
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("bookshelf.json")
        ensureDirs()
        load()
        scan()
    }

    private func ensureDirs() {
        if fm.fileExists(atPath: booksDir.path) == false {
            try? fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([Book].self, from: data) else {
            books = []
            return
        }
        books = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - 扫描与归位（核心修复）

    /// 扫描 App 目录，把根目录的书归位到 Books/，再和书架记录对齐
    func scan() {
        ensureDirs()
        adoptLooseFiles()
        refreshFromDisk()
    }

    /// 系统「拷贝到本 App」时文件会先落在 Documents/Inbox
    private var inboxDir: URL { docsDir.appendingPathComponent("Inbox") }

    /// 把 Documents 根目录 和 Inbox 里能识别的书都收进书架
    private func adoptLooseFiles() {
        for dir in [docsDir, inboxDir] {
            guard fm.fileExists(atPath: dir.path) else { continue }
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names {
                guard name != shelfFileName else { continue }
                let src = dir.appendingPathComponent(name)
                guard isRegularFile(src) else { continue }
                guard let format = BookFormat.detect(for: src) else { continue }

                let dest = uniqueDestination(preferredName: normalizedName(name, format: format))
                moveOrCopy(from: src, to: dest)
            }
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue == false
    }

    /// 移动失败就退化成「读进内存再写出去」
    @discardableResult
    private func moveOrCopy(from src: URL, to dest: URL) -> Bool {
        if (try? fm.moveItem(at: src, to: dest)) != nil { return true }
        if let data = try? Data(contentsOf: src) {
            if (try? data.write(to: dest, options: .atomic)) != nil {
                try? fm.removeItem(at: src)
                return true
            }
        }
        return false
    }

    /// 和书架记录对齐：删掉已不存在的文件，补上目录里没登记的文件
    private func refreshFromDisk() {
        let onDisk = (try? fm.contentsOfDirectory(atPath: booksDir.path)) ?? []
        let existing = Set(onDisk)

        books.removeAll { !existing.contains($0.fileName) }

        let known = Set(books.map { $0.fileName })
        for name in onDisk where known.contains(name) == false {
            let url = booksDir.appendingPathComponent(name)
            guard isRegularFile(url), let format = BookFormat.detect(for: url) else { continue }
            books.append(makeBook(for: url, format: format, fileName: name))
        }
        save()
    }

    /// 把没有扩展名 / 扩展名不对的文件补成正确的扩展名
    private func normalizedName(_ name: String, format: BookFormat) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == format.fileExtension { return name }
        let cleanBase = base.isEmpty ? "未命名" : base
        return "\(cleanBase).\(format.fileExtension)"
    }

    /// 生成不冲突的目标路径
    private func uniqueDestination(preferredName: String) -> URL {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var name = preferredName
        var index = 1
        while fm.fileExists(atPath: booksDir.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
            index += 1
        }
        return booksDir.appendingPathComponent(name)
    }

    // MARK: - 导入

    func importBook(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let format = BookFormat.detect(for: url) else {
            let ext = url.pathExtension.isEmpty ? "无扩展名" : url.pathExtension
            alertMessage = "这个文件读不出来（\(ext)），不是 TXT / EPUB / PDF / CBZ"
            return
        }
        ensureDirs()

        let dest = uniqueDestination(preferredName: normalizedName(url.lastPathComponent, format: format))

        var ok = false
        if (try? fm.copyItem(at: url, to: dest)) != nil { ok = true }

        if ok == false, let data = try? Data(contentsOf: url) {
            ok = (try? data.write(to: dest, options: .atomic)) != nil
        }

        if ok == false {
            // 最后用文件协调器读一次（iCloud 未下载完成的文件常见）
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
                if let data = try? Data(contentsOf: readURL) {
                    ok = (try? data.write(to: dest, options: .atomic)) != nil
                }
            }
            if ok == false {
                let reason = coordError?.localizedDescription ?? "文件无法读取"
                alertMessage = "导入失败：\(reason)"
                return
            }
        }

        // 从 Inbox 来的（微信分享「拷贝到」）拿走后把原件删掉，避免重复登记
        if url.path.contains("/Inbox/") {
            try? fm.removeItem(at: url)
        }

        // 复制成功后统一走扫描登记，避免重复登记
        scan()
        _ = format
    }

    private func makeBook(for url: URL, format: BookFormat, fileName: String) -> Book {
        var title = url.deletingPathExtension().lastPathComponent
        var author = "未知"
        var total = 0

        switch format {
        case .txt:
            if let data = try? Data(contentsOf: url), let text = TextLoader.decode(data) {
                total = text.utf16.count
                let firstLine = text
                    .components(separatedBy: "\n")
                    .first { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if firstLine.count > 0 && firstLine.count <= 24 && firstLine.contains("第") == false {
                    title = firstLine
                }
            }
        case .pdf:
            if let doc = PDFDocument(url: url) {
                total = doc.pageCount
                if let attrs = doc.documentAttributes {
                    if let t = attrs[PDFDocumentAttribute.titleAttribute] as? String, t.isEmpty == false {
                        title = t
                    }
                    if let a = attrs[PDFDocumentAttribute.authorAttribute] as? String, a.isEmpty == false {
                        author = a
                    }
                }
            }
        case .epub:
            total = 0
        case .comic:
            total = ComicLoader.listPages(url: url).count
        }

        return Book(title: title, author: author, format: format, fileName: fileName, totalUnits: total)
    }

    // MARK: - 删除 / 进度

    func delete(_ book: Book) {
        try? fm.removeItem(at: book.absoluteURL)
        books.removeAll { $0.id == book.id }
        save()
    }

    func updateProgress(bookID: UUID, location: Int, totalUnits: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].location = location
        if totalUnits > 0 { books[index].totalUnits = totalUnits }
        books[index].lastReadAt = Date()
        save()
    }

    func updateTitle(bookID: UUID, title: String, author: String, total: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        if title.isEmpty == false { books[index].title = title }
        if author.isEmpty == false { books[index].author = author }
        if total > 0 { books[index].totalUnits = total }
        save()
    }
}
