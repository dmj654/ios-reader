//
//  ReadingSettings.swift
//  ReaderApp
//
//  小说阅读 + 漫画阅读的个性化设置（全部持久化到 UserDefaults）
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

    var swatch: Color { background }
}

enum PageTurnStyle: String, CaseIterable, Codable, Identifiable {
    case slide
    case cover
    case none

    var id: String { rawValue }

    var name: String {
        switch self {
        case .slide: return "平移"
        case .cover: return "覆盖"
        case .none: return "无动画"
        }
    }
}

// MARK: - 漫画

/// 图片适配方式
enum ComicFitMode: String, CaseIterable, Identifiable {
    case screen   // 整页完整显示
    case width    // 铺满宽度
    case height   // 铺满高度

    var id: String { rawValue }

    var name: String {
        switch self {
        case .screen: return "适应屏幕"
        case .width: return "适应宽度"
        case .height: return "适应高度"
        }
    }

    var hint: String {
        switch self {
        case .screen: return "整页完整显示，四周留空，适合单页漫画"
        case .width: return "铺满屏幕宽度，高的页可上下滑动，适合竖条漫"
        case .height: return "铺满屏幕高度，宽的页可左右滑动"
        }
    }
}

/// 阅读方向
enum ComicDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var name: String {
        switch self {
        case .leftToRight: return "左 → 右"
        case .rightToLeft: return "右 → 左"
        }
    }

    var hint: String {
        switch self {
        case .leftToRight: return "国漫、欧美漫画"
        case .rightToLeft: return "日漫原版排版"
        }
    }
}

/// 阅读方式：分页翻页 / 竖向连续滚动
enum ComicReadMode: String, CaseIterable, Identifiable {
    case paged
    case continuous

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paged: return "分页翻页"
        case .continuous: return "竖向滚动"
        }
    }
}

/// 工具栏显示方式
enum ComicChromeMode: String, CaseIterable, Identifiable {
    case always      // 常驻
    case autoHide    // 点屏幕显示，几秒后自动隐藏
    case manual      // 点屏幕显示，再点隐藏

    var id: String { rawValue }

    var name: String {
        switch self {
        case .always: return "常驻显示"
        case .autoHide: return "点按 + 自动隐藏"
        case .manual: return "点按切换"
        }
    }
}

/// 阅读背景
enum ComicBackground: String, CaseIterable, Identifiable {
    case black
    case gray
    case white

    var id: String { rawValue }

    var name: String {
        switch self {
        case .black: return "纯黑"
        case .gray: return "深灰"
        case .white: return "白色"
        }
    }

    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(red: 0.13, green: 0.13, blue: 0.14)
        case .white: return .white
        }
    }
}

/// 点按区域
enum ComicTapZone: String, CaseIterable, Identifiable {
    case off
    case two
    case three

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "关闭"
        case .two: return "左右两区"
        case .three: return "左中右三区"
        }
    }

    var hint: String {
        switch self {
        case .off: return "点屏幕只控制工具栏，翻页靠左右滑动"
        case .two: return "点左边上一页、点右边下一页"
        case .three: return "左 1/3 上一页、中间出工具栏、右 1/3 下一页"
        }
    }
}

/// 全局阅读设置，自动持久化
final class ReadingSettings: ObservableObject {

    // 小说
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
    /// 正文自定义字体（PostScript 名），nil = 系统默认
    @Published var fontName: String? {
        didSet {
            if let fontName {
                defaults.set(fontName, forKey: Keys.fontName)
            } else {
                defaults.removeObject(forKey: Keys.fontName)
            }
        }
    }
    /// 段落之间的间距（pt）
    @Published var paragraphSpacing: Double {
        didSet { defaults.set(paragraphSpacing, forKey: Keys.paragraphSpacing) }
    }
    /// 正文加粗
    @Published var boldBody: Bool {
        didSet { defaults.set(boldBody, forKey: Keys.boldBody) }
    }
    /// 简繁显示方式
    @Published var scriptMode: TextScript {
        didSet { defaults.set(scriptMode.rawValue, forKey: Keys.scriptMode) }
    }

    // 漫画
    @Published var comicFit: ComicFitMode {
        didSet { defaults.set(comicFit.rawValue, forKey: Keys.comicFit) }
    }
    @Published var comicDirection: ComicDirection {
        didSet { defaults.set(comicDirection.rawValue, forKey: Keys.comicDirection) }
    }
    @Published var comicMode: ComicReadMode {
        didSet { defaults.set(comicMode.rawValue, forKey: Keys.comicMode) }
    }
    @Published var comicChrome: ComicChromeMode {
        didSet { defaults.set(comicChrome.rawValue, forKey: Keys.comicChrome) }
    }
    @Published var comicBackground: ComicBackground {
        didSet { defaults.set(comicBackground.rawValue, forKey: Keys.comicBackground) }
    }
    @Published var comicTapZone: ComicTapZone {
        didSet { defaults.set(comicTapZone.rawValue, forKey: Keys.comicTapZone) }
    }
    @Published var comicShowProgress: Bool {
        didSet { defaults.set(comicShowProgress, forKey: Keys.comicShowProgress) }
    }
    @Published var comicShowPageNumber: Bool {
        didSet { defaults.set(comicShowPageNumber, forKey: Keys.comicShowPageNumber) }
    }
    @Published var comicAutoTrim: Bool {
        didSet { defaults.set(comicAutoTrim, forKey: Keys.comicAutoTrim) }
    }
    @Published var comicKeepAwake: Bool {
        didSet { defaults.set(comicKeepAwake, forKey: Keys.comicKeepAwake) }
    }
    @Published var comicDoubleTapZoom: Bool {
        didSet { defaults.set(comicDoubleTapZoom, forKey: Keys.comicDoubleTapZoom) }
    }
    /// 阅读时叠加的压暗遮罩（0 = 不压暗）
    @Published var comicDim: Double {
        didSet { defaults.set(comicDim, forKey: Keys.comicDim) }
    }
    /// 工具栏自动隐藏延时（秒）
    @Published var comicAutoHideDelay: Double {
        didSet { defaults.set(comicAutoHideDelay, forKey: Keys.comicAutoHideDelay) }
    }
    /// 预读页数
    @Published var comicPreload: Int {
        didSet { defaults.set(comicPreload, forKey: Keys.comicPreload) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let theme = "reader.theme"
        static let pageTurn = "reader.pageTurn"
        static let fontName = "reader.fontName"
        static let paragraphSpacing = "reader.paragraphSpacing"
        static let boldBody = "reader.boldBody"
        static let scriptMode = "reader.scriptMode"
        static let comicFit = "reader.comicFit"
        static let comicDirection = "reader.comicDirection"
        static let comicMode = "reader.comicMode"
        static let comicChrome = "reader.comicChrome"
        static let comicBackground = "reader.comicBackground"
        static let comicTapZone = "reader.comicTapZone"
        static let comicShowProgress = "reader.comicShowProgress"
        static let comicShowPageNumber = "reader.comicShowPageNumber"
        static let comicAutoTrim = "reader.comicAutoTrim"
        static let comicKeepAwake = "reader.comicKeepAwake"
        static let comicDoubleTapZoom = "reader.comicDoubleTapZoom"
        static let comicDim = "reader.comicDim"
        static let comicAutoHideDelay = "reader.comicAutoHideDelay"
        static let comicPreload = "reader.comicPreload"
    }

    init() {
        let d = UserDefaults.standard

        let oldFitWidth = d.object(forKey: "reader.comicFitWidth") as? Bool
        let oldRTL = d.object(forKey: "reader.comicRTL") as? Bool

        self.fontSize = (d.object(forKey: Keys.fontSize) as? Double) ?? 19
        self.lineSpacing = (d.object(forKey: Keys.lineSpacing) as? Double) ?? 8
        self.theme = ReaderTheme(rawValue: d.string(forKey: Keys.theme) ?? "") ?? .paper
        self.pageTurn = PageTurnStyle(rawValue: d.string(forKey: Keys.pageTurn) ?? "") ?? .slide
        self.fontName = d.string(forKey: Keys.fontName)
        self.paragraphSpacing = (d.object(forKey: Keys.paragraphSpacing) as? Double) ?? 6
        self.boldBody = (d.object(forKey: Keys.boldBody) as? Bool) ?? false
        self.scriptMode = TextScript(rawValue: d.string(forKey: Keys.scriptMode) ?? "") ?? .auto

        self.comicFit = ComicFitMode(rawValue: d.string(forKey: Keys.comicFit) ?? "")
            ?? ((oldFitWidth == true) ? .width : .screen)
        self.comicDirection = ComicDirection(rawValue: d.string(forKey: Keys.comicDirection) ?? "")
            ?? ((oldRTL == true) ? .rightToLeft : .leftToRight)
        self.comicMode = ComicReadMode(rawValue: d.string(forKey: Keys.comicMode) ?? "") ?? .paged
        self.comicChrome = ComicChromeMode(rawValue: d.string(forKey: Keys.comicChrome) ?? "") ?? .autoHide
        self.comicBackground = ComicBackground(rawValue: d.string(forKey: Keys.comicBackground) ?? "") ?? .black
        self.comicTapZone = ComicTapZone(rawValue: d.string(forKey: Keys.comicTapZone) ?? "") ?? .three
        self.comicShowProgress = (d.object(forKey: Keys.comicShowProgress) as? Bool) ?? true
        self.comicShowPageNumber = (d.object(forKey: Keys.comicShowPageNumber) as? Bool) ?? true
        self.comicAutoTrim = (d.object(forKey: Keys.comicAutoTrim) as? Bool) ?? false
        self.comicKeepAwake = (d.object(forKey: Keys.comicKeepAwake) as? Bool) ?? true
        self.comicDoubleTapZoom = (d.object(forKey: Keys.comicDoubleTapZoom) as? Bool) ?? true
        self.comicDim = (d.object(forKey: Keys.comicDim) as? Double) ?? 0
        self.comicAutoHideDelay = (d.object(forKey: Keys.comicAutoHideDelay) as? Double) ?? 3
        self.comicPreload = (d.object(forKey: Keys.comicPreload) as? Int) ?? 2
    }

    /// 漫画设置恢复默认（小说设置不动）
    func resetComicDefaults() {
        comicFit = .screen
        comicDirection = .leftToRight
        comicMode = .paged
        comicChrome = .autoHide
        comicBackground = .black
        comicTapZone = .three
        comicShowProgress = true
        comicShowPageNumber = true
        comicAutoTrim = false
        comicKeepAwake = true
        comicDoubleTapZoom = true
        comicDim = 0
        comicAutoHideDelay = 3
        comicPreload = 2
    }
}
