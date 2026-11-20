//
//  TextScript.swift
//  ReaderApp
//
//  简繁转换：只在显示时转换，不改原始文本和阅读进度偏移
//

import Foundation

enum TextScript: String, CaseIterable, Codable, Identifiable {
    case auto        // 原文，不转
    case simplified  // 转简体
    case traditional  // 转繁体

    var id: String { rawValue }

    var name: String {
        switch self {
        case .auto: return "原文"
        case .simplified: return "简体"
        case .traditional: return "繁体"
        }
    }

    static func convert(_ text: String, mode: TextScript) -> String {
        guard text.isEmpty == false else { return text }
        switch mode {
        case .auto:
            return text
        case .simplified:
            let transform = StringTransform(rawValue: "TraditionalToSimplifiedChinese")
            return text.applyingTransform(transform, reverse: false) ?? text
        case .traditional:
            let transform = StringTransform(rawValue: "SimplifiedToTraditionalChinese")
            return text.applyingTransform(transform, reverse: false) ?? text
        }
    }
}
