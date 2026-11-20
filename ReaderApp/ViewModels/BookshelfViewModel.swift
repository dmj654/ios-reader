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
    @Published var bookmarks: [Bookmark] = []

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
        loadBookmarks()
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

                let dest = uniqueDestination(preferredName: BookshelfViewModel.normalizedName(name, format: format))
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
        var queued: [(String, BookFormat)] = []
        for name in onDisk where known.contains(name) == false {
            let url = booksDir.appendingPathComponent(name)
            guard isRegularFile(url), let format = BookFormat.detect(for: url) else { continue }
            // 先用文件名占位，元数据（书名/作者/总页数）后台再补，避免卡住界面
            books.append(Book(title: url.deletingPathExtension().lastPathComponent,
                              author: "未知",
                              format: format,
                              fileName: name,
                              totalUnits: 0))
            queued.append((name, format))
        }
        save()
        for item in queued {
            requestMetadata(fileName: item.0, format: item.1)
        }
    }

    /// 把没有扩展名 / 扩展名不对的文件补成正确的扩展名
    nonisolated static func normalizedName(_ name: String, format: BookFormat) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == format.fileExtension { return name }
        let cleanBase = base.isEmpty ? "未命名" : base
        return "\(cleanBase).\(format.fileExtension)"
    }

    /// 生成不冲突的目标路径（实例侧包一层）
    private func uniqueDestination(preferredName: String) -> URL {
        booksDir.appendingPathComponent(
            BookshelfViewModel.uniqueName(in: booksDir, preferredName: preferredName)
        )
    }

    nonisolated static func uniqueName(in dir: URL, preferredName: String) -> String {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var name = preferredName
        var index = 1
        let fm = FileManager.default
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
            index += 1
        }
        return name
    }

    // MARK: - 导入

    // MARK: - 导入（后台复制 + 先上架再补元数据，避免大文件卡界面）

    struct BookMeta: @unchecked Sendable {
        var title: String = ""
        var author: String = ""
        var total: Int = 0
    }

    struct ImportOutcome: @unchecked Sendable {
        var fileName: String?
        var format: BookFormat?
        var error: String?
    }

    /// 返回 nil 表示成功；非 nil 是给用户看的失败原因
    func importBook(from url: URL) async -> String? {
        ensureDirs()
        let dir = booksDir

        let outcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
            BookshelfViewModel.copyIntoLibrary(source: url, booksDir: dir)
        }.value

        if let error = outcome.error { return error }
        guard let fileName = outcome.fileName, let format = outcome.format else {
            return "导入失败：文件没能存进来"
        }

        let title = (fileName as NSString).deletingPathExtension
        if books.contains(where: { $0.fileName == fileName }) == false {
            books.append(Book(title: title, author: "未知", format: format, fileName: fileName, totalUnits: 0))
            save()
        }
        requestMetadata(fileName: fileName, format: format)
        return nil
    }

    private nonisolated static func copyIntoLibrary(source: URL, booksDir: URL) -> ImportOutcome {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        guard let format = BookFormat.detect(for: source) else {
            let ext = source.pathExtension.isEmpty ? "无扩展名" : source.pathExtension
            return ImportOutcome(error: "这个文件读不出来（\(ext)），不是 TXT / EPUB / PDF / CBZ")
        }

        let fm = FileManager.default
        let name = uniqueName(in: booksDir, preferredName: normalizedName(source.lastPathComponent, format: format))
        let dest = booksDir.appendingPathComponent(name)

        if (try? fm.copyItem(at: source, to: dest)) == nil {
            var copied = false
            if let data = try? Data(contentsOf: source) {
                copied = (try? data.write(to: dest, options: .atomic)) != nil
            }
            if copied == false {
                // iCloud 未下载完成的文件常见，最后用文件协调器读一次
                var coordError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { readURL in
                    if let data = try? Data(contentsOf: readURL) {
                        copied = (try? data.write(to: dest, options: .atomic)) != nil
                    }
                }
                if copied == false {
                    return ImportOutcome(error: "导入失败：\(coordError?.localizedDescription ?? "文件无法读取")")
                }
            }
        }

        // 微信「拷贝到」进 Inbox 的原件删掉，避免重复登记
        if source.path.contains("/Inbox/") { try? fm.removeItem(at: source) }
        return ImportOutcome(fileName: name, format: format)
    }

    /// 已在后台跑元数据的文件，避免重复请求
    private var metadataPending: Set<String> = []

    private func requestMetadata(fileName: String, format: BookFormat) {
        guard metadataPending.contains(fileName) == false else { return }
        metadataPending.insert(fileName)

        let url = booksDir.appendingPathComponent(fileName)
        Task.detached(priority: .utility) { [weak self] in
            let meta = BookshelfViewModel.metadata(for: url, format: format)
            await MainActor.run {
                guard let self else { return }
                self.metadataPending.remove(fileName)
                guard let index = self.books.firstIndex(where: { $0.fileName == fileName }) else { return }
                if meta.title.isEmpty == false { self.books[index].title = meta.title }
                if meta.author.isEmpty == false { self.books[index].author = meta.author }
                if meta.total > 0 { self.books[index].totalUnits = meta.total }
                self.save()
            }
        }
    }

    nonisolated static func metadata(for url: URL, format: BookFormat) -> BookMeta {
        var meta = BookMeta()
        var title = url.deletingPathExtension().lastPathComponent
        var author = "未知"
        var total = 0

        switch format {
        case .txt:
            // 只读开头一段拿书名，绝不把整本读进内存（大合集会把 App 撑爆）；
            // 总字数留空，等真正打开时由阅读器补上
            if let head = BookshelfViewModel.head(of: url, limit: 65_536),
               let text = TextLoader.decode(head, allowPartial: true) {
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
                    if let t = attrs[PDFDocumentAttribute.titleAttribute] as? String, t.isEmpty == false { title = t }
                    if let a = attrs[PDFDocumentAttribute.authorAttribute] as? String, a.isEmpty == false { author = a }
                }
            }
        case .epub:
            total = 0
        case .comic:
            total = ComicLoader.listPages(url: url).count
        }

        meta.title = title
        meta.author = author
        meta.total = total
        return meta
    }

    /// 只读文件开头一小段，用于嗅探 / 取标题，不占大内存
    nonisolated static func head(of url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }

    // MARK: - 删除 / 进度

    func delete(_ book: Book) {
        try? fm.removeItem(at: book.absoluteURL)
        TextCache.remove(bookID: book.id)
        TextCache.removeImages(bookID: book.id)
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

// MARK: - 书签

extension BookshelfViewModel {

    private var bookmarksURL: URL {
        docsDir.appendingPathComponent("bookmarks.json")
    }

    func loadBookmarks() {
        guard let data = try? Data(contentsOf: bookmarksURL),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            bookmarks = []
            return
        }
        bookmarks = decoded
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: bookmarksURL, options: .atomic)
    }

    func bookmarks(for bookID: UUID) -> [Bookmark] {
        bookmarks
            .filter { $0.bookID == bookID }
            .sorted { $0.offset < $1.offset }
    }

    func isBookmarked(bookID: UUID, offset: Int) -> Bool {
        bookmarks.contains { $0.bookID == bookID && $0.offset == offset }
    }

    /// 同一个位置再点一次就是取消
    func toggleBookmark(bookID: UUID, offset: Int, chapter: String, snippet: String) {
        if let index = bookmarks.firstIndex(where: { $0.bookID == bookID && $0.offset == offset }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(Bookmark(bookID: bookID, offset: offset, chapter: chapter, snippet: snippet))
        }
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }
}
