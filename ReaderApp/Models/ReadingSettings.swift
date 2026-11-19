//
//  ReadingSettings.swift
//  ReaderApp
//
//  阅读个性化设置：字号、行距、背景主题、翻页方式
//

import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Codable, Identifiable {
    case paper   // 米黄护眼
    case white   // 纯白
    case green   // 豆沙绿
    case night   // 夜间

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: return "米黄"
        case .white: return "纯白"
        case .green: return "护眼"
        case .night: return "夜间"
        }
    }

    var background: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.94, blue: 0.88)
        case .white: return Color.white
        case .green: return Color(red: 0.80, green: 0.87, blue: 0.79)
        case .night: return Color(red: 0.10, green: 0.10, blue: 0.11)
        }
    }

    var foreground: Color {
        switch self {
        case .paper: return Color(red: 0.18, green: 0.15, blue: 0.12)
        case .white: return Color(red: 0.12, green: 0.12, blue: 0.13)
        case .green: return Color(red: 0.15, green: 0.18, blue: 0.15)
        case .night: return Color(red: 0.78, green: 0.78, blue: 0.80)
        }
    }

    var isDark: Bool { self == .night }

    /// 设置面板里的圆圈预览色
    var swatch: Color { background }
}

enum PageTurnStyle: String, CaseIterable, Codable, Identifiable {
    case slide   // 平移
    case cover   // 覆盖
    case none    // 无动画

    var id: String { rawValue }

    var name: String {
        switch self {
        case .slide: return "平移"
        case .cover: return "覆盖"
        case .none: return "无动画"
        }
    }
}

/// 全局阅读设置，自动持久化
final class ReadingSettings: ObservableObject {
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) }
    }
    @Published var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var pageTurn: PageTurnStyle {
        didSet { defaults.set(pageTurn.rawValue, forKey: Keys.pageTurn) }
    }
    /// 漫画：图片铺满宽度（适合竖条漫），关闭则整页显示
    @Published var comicFitWidth: Bool {
        didSet { defaults.set(comicFitWidth, forKey: Keys.comicFitWidth) }
    }
    /// 漫画：从右往左翻页（日漫）
    @Published var comicRTL: Bool {
        didSet { defaults.set(comicRTL, forKey: Keys.comicRTL) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let theme = "reader.theme"
        static let pageTurn = "reader.pageTurn"
        static let comicFitWidth = "reader.comicFitWidth"
        static let comicRTL = "reader.comicRTL"
    }

    init() {
        let d = UserDefaults.standard
        let size = d.object(forKey: Keys.fontSize) as? Double
        let spacing = d.object(forKey: Keys.lineSpacing) as? Double
        let themeRaw = d.string(forKey: Keys.theme)
        let turnRaw = d.string(forKey: Keys.pageTurn)
        let fitWidth = d.object(forKey: Keys.comicFitWidth) as? Bool
        let rtl = d.object(forKey: Keys.comicRTL) as? Bool

        self.fontSize = size ?? 19
        self.lineSpacing = spacing ?? 8
        self.theme = ReaderTheme(rawValue: themeRaw ?? "") ?? .paper
        self.pageTurn = PageTurnStyle(rawValue: turnRaw ?? "") ?? .slide
        self.comicFitWidth = fitWidth ?? false
        self.comicRTL = rtl ?? false
    }
}
