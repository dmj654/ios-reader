//
//  HomeSummaryTests.swift
//  ReaderAppTests
//
//  主页摘要纯逻辑：最近在读、最近导入封面、历史记录数、可用书源数。
//

import XCTest
@testable import ReaderApp

final class HomeSummaryTests: XCTestCase {

    private func makeBook(
        id: UUID = UUID(),
        title: String,
        addedAt: Date,
        lastReadAt: Date? = nil,
        location: Int = 0,
        totalUnits: Int = 100
    ) -> Book {
        var book = Book(title: title, author: "作者", format: .txt,
                        fileName: "\(id.uuidString).txt", totalUnits: totalUnits)
        book.id = id
        book.addedAt = addedAt
        book.lastReadAt = lastReadAt
        book.location = location
        return book
    }

    func testMostRecentBookPicksLatestLastReadAt() {
        let older = makeBook(title: "旧书", addedAt: Date(),
                             lastReadAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeBook(title: "新书", addedAt: Date(),
                             lastReadAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(HomeSummary.mostRecentBook(books: [older, newer])?.id, newer.id)
    }

    func testMostRecentBookFallsBackToAddedAt() {
        let earlierAdded = makeBook(title: "早导入", addedAt: Date(timeIntervalSince1970: 1_000))
        let laterAdded = makeBook(title: "晚导入", addedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(HomeSummary.mostRecentBook(books: [earlierAdded, laterAdded])?.id, laterAdded.id)
    }

    func testRecentCoversLimitedAndSortedByAddedAt() {
        let books = (0..<6).map { index in
            makeBook(title: "书\(index)", addedAt: Date(timeIntervalSince1970: Double(index * 100)))
        }

        let covers = HomeSummary.recentCovers(books: books, limit: 4)

        XCTAssertEqual(covers.count, 4)
        XCTAssertEqual(covers.map(\.title), ["书5", "书4", "书3", "书2"])
    }

    func testHistoryCountMatchesPresentBooks() {
        let bookA = makeBook(title: "A", addedAt: Date())
        let bookB = makeBook(title: "B", addedAt: Date())
        var statA = BookStat()
        statA.lastAt = Date()
        var statB = BookStat()
        statB.lastAt = Date()
        let stats: [String: BookStat] = [
            bookA.id.uuidString: statA,
            bookB.id.uuidString: statB,
            UUID().uuidString: BookStat()
        ]

        XCTAssertEqual(HomeSummary.historyCount(books: [bookA, bookB], stats: stats), 2)
    }

    func testUsableSourceCountCountsOnlyEnabledUsable() {
        var usable = BookSource()
        usable.enabled = true
        usable.baseUrl = "https://example.com"

        var disabled = BookSource()
        disabled.enabled = false
        disabled.baseUrl = "https://disabled.example.com"

        XCTAssertEqual(HomeSummary.usableSourceCount(sources: [usable, disabled]), 1)
    }
}
