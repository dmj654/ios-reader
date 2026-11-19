//
//  BookshelfViewModel.swift
//  ReaderApp
//
//  书架：导入 / 删除 / 排序 / 进度保存
//

import Foundation
import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class BookshelfViewModel: ObservableObject {

    @Published var books: [Book] = []
    @Published var message: String?

    private let storeURL: URL

    var booksDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Books")
        if FileManager.default.fileExists(atPath: dir.path) == false {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = docs.appendingPathComponent("bookshelf.json")
        load()
        syncWithDisk()
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

    /// 把文件名和记录对齐：删掉记录里已经不存在的文件，补上目录里没登记的文件
    func syncWithDisk() {
        let fm = FileManager.default
        let onDisk = (try? fm.contentsOfDirectory(atPath: booksDir.path)) ?? []
        books.removeAll { book in
            !onDisk.contains(book.fileName)
        }
        let known = Set(books.map { $0.fileName })
        for name in onDisk where known.contains(name) == false {
            let url = booksDir.appendingPathComponent(name)
            if let format = BookFormat.from(fileURL: url) {
                let book = makeBook(for: url, format: format, fileName: name)
                books.append(book)
            }
        }
        save()
    }

    // MARK: - 导入

    func importBook(from url: URL) {
        let fm = FileManager.default
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let format = BookFormat.from(fileURL: url) else {
            message = "不支持的格式：.\(url.pathExtension)"
            return
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var destName = "\(baseName).\(ext)"
        var index = 1
        while fm.fileExists(atPath: booksDir.appendingPathComponent(destName).path) {
            destName = "\(baseName)_\(index).\(ext)"
            index += 1
        }
        let destURL = booksDir.appendingPathComponent(destName)

        do {
            try fm.copyItem(at: url, to: destURL)
            let book = makeBook(for: destURL, format: format, fileName: destName)
            books.insert(book, at: 0)
            save()
            message = "已导入《\(book.title)》"
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    private func makeBook(for url: URL, format: BookFormat, fileName: String) -> Book {
        var title = url.deletingPathExtension().lastPathComponent
        var author = "未知"
        var total = 0

        switch format {
        case .txt:
            if let data = try? Data(contentsOf: url), let text = TextLoader.decode(data) {
                total = text.utf16.count
                // 用第一行非空内容当书名，如果是章节名就保留文件名
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
            // 导入时不解析全文（大部头会卡住界面），等打开阅读时再解析并回填书名
            total = 0
        case .comic:
            total = ComicLoader.listPages(url: url).count
        }

        return Book(title: title, author: author, format: format, fileName: fileName, totalUnits: total)
    }

    // MARK: - 删除 / 进度

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: book.absoluteURL)
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

    /// EPUB 解析后补全书名 / 作者
    func updateTitle(bookID: UUID, title: String, author: String, total: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        if title.isEmpty == false { books[index].title = title }
        if author.isEmpty == false { books[index].author = author }
        if total > 0 { books[index].totalUnits = total }
        save()
    }

    /// 最近在读
    var recentBooks: [Book] {
        books.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }
}
