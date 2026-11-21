//
//  HistoryModelTests.swift
//  ReaderAppTests
//
//  历史列表：书目与统计匹配、按时间倒序、孤立统计剔除；清除单条记录持久化。
//

import XCTest
@testable import ReaderApp

final class HistoryModelTests: XCTestCase {

    private func makeBook(id: UUID, title: String, lastReadAt: Date) -> Book {
        var book = Book(title: title, author: "作者", format: .txt,
                        fileName: "\(id.uuidString).txt", totalUnits: 100)
        book.id = id
        book.lastReadAt = lastReadAt
        return book
    }

    func testEntriesMatchPresentBooksAndSortByLastAtDesc() {
        let older = makeBook(id: UUID(), title: "旧书", lastReadAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeBook(id: UUID(), title: "新书", lastReadAt: Date(timeIntervalSince1970: 2_000))

        var statOlder = BookStat()
        statOlder.lastAt = older.lastReadAt ?? Date()
        var statNewer = BookStat()
        statNewer.lastAt = newer.lastReadAt ?? Date()

        var stats: [String: BookStat] = [
            older.id.uuidString: statOlder,
            newer.id.uuidString: statNewer,
            UUID().uuidString: BookStat()
        ]

        let entries = HistoryModel.entries(books: [older, newer], stats: stats)

        XCTAssertEqual(entries.map(\.id), [newer.id, older.id])
        XCTAssertEqual(entries.count, 2)
    }

    func testClearBookRemovesPersistedRecord() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("historytest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("stats.json")

        let bookA = UUID()
        let bookB = UUID()
        var statA = BookStat()
        statA.lastAt = Date()
        var statB = BookStat()
        statB.lastAt = Date()
        let payload = StatsPayload(version: 1, days: [:], books: [
            bookA.uuidString: statA,
            bookB.uuidString: statB
        ])
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)

        let store = ReadingStatsStore(storeURL: url)
        store.clearBook(id: bookA)

        let reloaded = ReadingStatsStore(storeURL: url)
        XCTAssertNil(reloaded.books[bookA.uuidString])
        XCTAssertNotNil(reloaded.books[bookB.uuidString])
    }
}
