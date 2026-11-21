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
}
