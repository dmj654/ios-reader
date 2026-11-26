//
//  AppThemeTests.swift
//  ReaderAppTests
//
//  设计系统常量：圆角层级、阴影参数与配色不塌缩。
//

import XCTest
@testable import ReaderApp

final class AppThemeTests: XCTestCase {

    func testCornerRadiusHierarchy() {
        XCTAssertGreaterThan(AppTheme.radiusCard, AppTheme.radiusInner)
        XCTAssertGreaterThan(AppTheme.radiusInner, 0)
        XCTAssertGreaterThan(AppTheme.radiusChip, AppTheme.radiusCard)
    }

    func testCardShadow() {
        XCTAssertGreaterThan(AppTheme.cardShadow.radius, 0)
        XCTAssertEqual(AppTheme.cardShadow.y, 2)
        XCTAssertGreaterThan(AppTheme.cardShadow.x, -1)
    }

    func testPaletteExposed() {
        // 常量必须可被引用（编译期即保证存在），这里再断言强调色与底色非空层级。
        XCTAssertNotNil(AppTheme.background)
        XCTAssertNotNil(AppTheme.card)
        XCTAssertNotNil(AppTheme.accent)
        XCTAssertNotNil(AppTheme.accentSoft)
        XCTAssertNotNil(AppTheme.primary)
        XCTAssertNotNil(AppTheme.secondary)
        XCTAssertNotNil(AppTheme.tertiary)
    }

    /// 悬浮玻璃导航的几何：高 64、圆角 24、左右 16、离底 12
    func testFloatingGlassMetrics() {
        XCTAssertEqual(AppTheme.glassHeight, 64)
        XCTAssertEqual(AppTheme.glassRadius, 24)
        XCTAssertEqual(AppTheme.glassInset, 16)
        XCTAssertEqual(AppTheme.glassBottom, 12)
        // 内容留白要能完整容下玻璃条，否则列表最后一行会被压住
        XCTAssertGreaterThanOrEqual(AppTheme.tabBarReserve, AppTheme.glassHeight + AppTheme.glassBottom)
    }

    /// 阅读工具条与底栏共用同一套玻璃尺寸
    func testReaderChromeMatchesGlass() {
        XCTAssertEqual(ReaderChromeMetrics.height, AppTheme.glassHeight)
        XCTAssertEqual(ReaderChromeMetrics.radius, AppTheme.glassRadius)
        XCTAssertEqual(ReaderChromeMetrics.bottomGap, AppTheme.glassBottom)
        XCTAssertEqual(ReaderChromeMetrics.horizontalInset, AppTheme.glassInset)
    }
}
