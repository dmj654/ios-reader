//
//  TextCacheTests.swift
//  ReaderAppTests
//
//  解析缓存往返：保存后命中；源文件变化后指纹失效；空章节不落缓存。
//

import XCTest
@testable import ReaderApp

final class TextCacheTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("textcache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRoundTripHitAfterSave() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("src.txt")
        try "正文内容".data(using: .utf8)!.write(to: source, options: .atomic)

        let bookID = UUID()
        let text = BookText(
            title: "书名",
            author: "作者",
            chapters: [Chapter(title: "第一章", text: "章节正文")]
        )
        TextCache.save(text, bookID: bookID, source: source, dir: dir)

        let loaded = TextCache.load(bookID: bookID, source: source, dir: dir)
        XCTAssertEqual(loaded?.title, "书名")
        XCTAssertEqual(loaded?.author, "作者")
        XCTAssertEqual(loaded?.chapters.count, 1)
        XCTAssertEqual(loaded?.chapters.first?.text, "章节正文")
    }

    func testCacheMissWhenSourceChanged() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("src.txt")
        try "旧内容".data(using: .utf8)!.write(to: source, options: .atomic)

        let bookID = UUID()
        let text = BookText(title: "书名", author: "作者",
                            chapters: [Chapter(title: "第一章", text: "正文")])
        TextCache.save(text, bookID: bookID, source: source, dir: dir)

        // 源文件被替换（内容 / 大小 / 修改时间都变了），缓存必须作废
        try "新的更长的内容".data(using: .utf8)!.write(to: source, options: .atomic)

        XCTAssertNil(TextCache.load(bookID: bookID, source: source, dir: dir))
    }

    func testEmptyChaptersNotCached() throws {
        let dir = try makeTempDir()
        let source = dir.appendingPathComponent("src.txt")
        try "x".data(using: .utf8)!.write(to: source, options: .atomic)

        let bookID = UUID()
        let empty = BookText(title: "空", author: "-", chapters: [])
        TextCache.save(empty, bookID: bookID, source: source, dir: dir)

        XCTAssertNil(TextCache.load(bookID: bookID, source: source, dir: dir))
    }
}
