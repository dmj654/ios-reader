//
//  BackupRoundTripTests.swift
//  ReaderAppTests
//
//  备份 / 恢复往返：主页布局随备份包打包，清掉本地文件后从备份恢复仍一致。
//

import XCTest
@testable import ReaderApp

final class BackupRoundTripTests: XCTestCase {

    func testHomeLayoutIsIncludedAndRestored() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("backuptest-\(UUID().uuidString)")
        let docs = root.appendingPathComponent("Documents")
        let appSupport = root.appendingPathComponent("AppSupport")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let layout = HomeLayout(order: [.search, .discover, .local], hidden: [.history])
        let layoutURL = appSupport.appendingPathComponent("HomeLayout.json")
        try JSONEncoder().encode(layout).write(to: layoutURL, options: .atomic)

        let store = BackupStore(docsDir: docs, appSupport: appSupport)
        let data = try store.currentBackupData()

        // 清掉本地布局，再从备份包恢复
        try FileManager.default.removeItem(at: layoutURL)
        try store.restore(data: data)

        let restoredData = try Data(contentsOf: layoutURL)
        let restored = try JSONDecoder().decode(HomeLayout.self, from: restoredData)
        XCTAssertEqual(restored.order, layout.order)
        XCTAssertEqual(restored.hidden, layout.hidden)
    }
}
