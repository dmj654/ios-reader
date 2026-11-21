//
//  HomeLayoutStoreTests.swift
//  ReaderAppTests
//
//  主页布局仓库：排序 / 显隐 / 恢复默认 / 持久化回读 / 容错解码。
//

import XCTest
@testable import ReaderApp

final class HomeLayoutStoreTests: XCTestCase {

    private func makeStore() throws -> HomeLayoutStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hometest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return HomeLayoutStore(storeURL: dir.appendingPathComponent("HomeLayout.json"))
    }

    func testDefaultLayout() {
        let store = try? makeStore()
        XCTAssertEqual(store?.layout.order, HomeCardID.allCases)
        XCTAssertEqual(store?.layout.hidden, [])
    }

    func testMoveReordersVisibleCards() {
        let store = try! makeStore()
        store.move(fromOffsets: IndexSet([0]), toOffsets: 3)

        XCTAssertEqual(store.layout.order, [
            .local, .history, .sources, .continueReading, .discover, .search
        ])
        XCTAssertEqual(store.layout.hidden, [])
    }

    func testHideMovesCardToHidden() {
        let store = try! makeStore()
        store.hide(.local)

        XCTAssertFalse(store.layout.order.contains(.local))
        XCTAssertEqual(store.layout.hidden, [.local])
    }

    func testRestoreReturnsCardToOrderEnd() {
        let store = try! makeStore()
        store.hide(.local)
        store.restore(.local)

        XCTAssertEqual(store.layout.order.last, .local)
        XCTAssertEqual(store.layout.hidden, [])
    }

    func testRestoreAlreadyVisibleIsNoop() {
        let store = try! makeStore()
        let before = store.layout.order
        store.restore(.search)

        XCTAssertEqual(store.layout.order, before)
        XCTAssertEqual(store.layout.hidden, [])
    }

    func testResetDefaultsRestoresAllCards() {
        let store = try! makeStore()
        store.hide(.continueReading)
        store.hide(.discover)
        store.resetDefaults()

        XCTAssertEqual(store.layout.order, HomeCardID.allCases)
        XCTAssertEqual(store.layout.hidden, [])
    }

    func testLayoutPersistsAcrossReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hometest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("HomeLayout.json")

        let first = HomeLayoutStore(storeURL: url)
        first.hide(.history)
        first.move(fromOffsets: IndexSet([0]), toOffsets: 2)

        let second = HomeLayoutStore(storeURL: url)
        XCTAssertTrue(second.layout.hidden.contains(.history))
        XCTAssertEqual(second.layout.order, first.layout.order)
    }

    func testDecodeToleratesUnknownAndDuplicateIDs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hometest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("HomeLayout.json")

        let raw = """
        {"order":["local","local","history-unknown"],"hidden":["history"]}
        """
        try Data(raw.utf8).write(to: url, options: .atomic)

        let store = HomeLayoutStore(storeURL: url)
        XCTAssertEqual(store.layout.order, [.local])
        XCTAssertEqual(store.layout.hidden, [.history])
    }
}
