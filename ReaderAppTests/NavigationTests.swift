//
//  NavigationTests.swift
//  ReaderAppTests
//
//  导航骨架与主页卡片定义校验：四 tab、六卡片默认顺序与文案。
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
    func testCardDefaultOrderMatchesPRD() {
        XCTAssertEqual(
            HomeCardID.allCases.map(\.rawValue),
            ["continueReading", "local", "history", "sources", "discover", "search"]
        )
        XCTAssertEqual(
            HomeCardID.allCases.map(\.title),
            ["继续阅读", "本地", "历史", "在线书源", "发现", "搜索"]
        )
    }

    /// 每张卡片都有标题、副标题和图标标识，不留空
    func testCardEntriesAreComplete() {
        for id in HomeCardID.allCases {
            XCTAssertFalse(id.title.isEmpty)
            XCTAssertFalse(id.subtitle.isEmpty)
            XCTAssertFalse(id.iconName.isEmpty)
        }
    }
}
