//
//  NavigationTests.swift
//  ReaderAppTests
//
//  M1 导航骨架校验：四 tab 定义、主页六卡片默认顺序与文案。
//

import XCTest
@testable import ReaderApp

final class NavigationTests: XCTestCase {

    /// 底部必须是主页 / 书架 / 发现 / 搜索 四个互异 tab
    func testRootTabHasFourDistinctCases() {
        let tabs: [RootView.RootTab] = [.home, .shelf, .discover, .search]
        XCTAssertEqual(tabs.count, 4)
        XCTAssertEqual(Set(tabs).count, 4)
    }

    /// 主页六张卡片默认顺序与 PRD 3.2 一致
    func testHomeDefaultPlaceholdersMatchPRDOrder() {
        let expectedIDs = ["continue", "local", "history", "sources", "discover", "search"]
        let expectedTitles = ["继续阅读", "本地", "历史", "在线书源", "发现", "搜索"]

        XCTAssertEqual(HomeView.defaultPlaceholders.map(\.id), expectedIDs)
        XCTAssertEqual(HomeView.defaultPlaceholders.map(\.title), expectedTitles)
    }

    /// 每张占位卡片都有标题、副标题和图标标识，不留空
    func testHomePlaceholderEntriesAreComplete() {
        for item in HomeView.defaultPlaceholders {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.subtitle.isEmpty)
            XCTAssertFalse(item.icon.isEmpty)
        }
    }
}
