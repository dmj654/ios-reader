//
//  BookshelfReconcileTests.swift
//  ReaderAppTests
//
//  书架磁盘对齐：保留在架书目与进度，剔除已不在磁盘的书，补登记新文件。
//

import XCTest
@testable import ReaderApp

final class BookshelfReconcileTests: XCTestCase {

    private func makeBook(title: String, fileName: String, format: BookFormat, location: Int = 0) -> Book {
        var book = Book(title: title, author: "作者", format: format,
                        fileName: fileName, totalUnits: 100)
        book.location = location
        return book
    }

    func testReconcileKeepsExistingDropsMissingAddsNew() {
        let kept = makeBook(title: "在架", fileName: "kept.epub", format: .epub, location: 40)
        let gone = makeBook(title: "已删", fileName: "gone.txt", format: .txt)

        let entries: [BookshelfViewModel.DiskEntry] = [
            .init(fileName: "kept.epub", format: .epub),
            .init(fileName: "new.cbz", format: .comic)
        ]

        let result = BookshelfViewModel.reconcile(current: [kept, gone], entries: entries)

        XCTAssertEqual(result.books.map(\.fileName).sorted(), ["kept.epub", "new.cbz"])
        XCTAssertEqual(result.books.first(where: { $0.fileName == "kept.epub" })?.location, 40)
        XCTAssertEqual(result.queued.map(\.fileName), ["new.cbz"])
    }

    func testReconcileNewEntryIsPlaceholderWithoutProgress() {
        let entries: [BookshelfViewModel.DiskEntry] = [
            .init(fileName: "fresh.txt", format: .txt)
        ]

        let result = BookshelfViewModel.reconcile(current: [], entries: entries)

        XCTAssertEqual(result.books.count, 1)
        let book = result.books[0]
        XCTAssertEqual(book.title, "fresh")
        XCTAssertEqual(book.format, .txt)
        XCTAssertEqual(book.location, 0)
        XCTAssertEqual(book.totalUnits, 0)
    }

    func testReconcileEmptyDiskRemovesAll() {
        let current = [
            makeBook(title: "A", fileName: "a.txt", format: .txt),
            makeBook(title: "B", fileName: "b.epub", format: .epub)
        ]

        let result = BookshelfViewModel.reconcile(current: current, entries: [])

        XCTAssertTrue(result.books.isEmpty)
        XCTAssertTrue(result.queued.isEmpty)
    }
}
