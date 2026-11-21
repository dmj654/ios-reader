//
//  HomeCard.swift
//  ReaderApp
//
//  主页卡片定义与主页布局持久化模型。
//  order：可见卡片顺序；hidden：被隐藏的卡片。
//

import Foundation

/// 主页六张卡片标识（顺序即 PRD 3.2 默认顺序）
enum HomeCardID: String, Codable, CaseIterable, Identifiable {
    case continueReading
    case local
    case history
    case sources
    case discover
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueReading: return "继续阅读"
        case .local: return "本地"
        case .history: return "历史"
        case .sources: return "在线书源"
        case .discover: return "发现"
        case .search: return "搜索"
        }
    }

    var subtitle: String {
        switch self {
        case .continueReading: return "最近在读"
        case .local: return "导入的小说与漫画"
        case .history: return "读过的记录"
        case .sources: return "可用书源"
        case .discover: return "书单与分类"
        case .search: return "书名 / 作者"
        }
    }

    var iconName: String {
        switch self {
        case .continueReading: return "bookmark"
        case .local: return "folder"
        case .history: return "clock"
        case .sources: return "list.bullet"
        case .discover: return "compass"
        case .search: return "magnifyingglass"
        }
    }
}

/// 主页布局：可见顺序 + 隐藏列表
struct HomeLayout: Codable, Equatable {
    var order: [HomeCardID]
    var hidden: [HomeCardID]

    static let `default` = HomeLayout(order: HomeCardID.allCases, hidden: [])

    enum CodingKeys: String, CodingKey {
        case order, hidden
    }

    init(order: [HomeCardID], hidden: [HomeCardID]) {
        self.order = order
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = Self.decodeIDList(c, .order)
        hidden = Self.decodeIDList(c, .hidden)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue), forKey: .hidden)
    }

    /// 数组里遇到未知 raw 值时跳过，而不是整包解码失败
    private static func decodeIDList(_ c: KeyedDecodingContainer, _ key: CodingKeys) -> [HomeCardID] {
        guard let raw = try? c.decode([String].self, forKey: key) else { return [] }
        return raw.compactMap { HomeCardID(rawValue: $0) }
    }

    /// 校验并补齐：去掉重复与未知项；可见列表为空时回退默认
    func normalized() -> HomeLayout {
        var seen = Set<HomeCardID>()
        var cleanedOrder: [HomeCardID] = []
        for id in order where seen.contains(id) == false {
            seen.insert(id)
            cleanedOrder.append(id)
        }
        var cleanedHidden: [HomeCardID] = []
        var hiddenSeen = Set<HomeCardID>()
        for id in hidden where seen.contains(id) == false {
            if hiddenSeen.contains(id) { continue }
            hiddenSeen.insert(id)
            cleanedHidden.append(id)
        }
        if cleanedOrder.isEmpty {
            return HomeLayout.default
        }
        return HomeLayout(order: cleanedOrder, hidden: cleanedHidden)
    }
}
