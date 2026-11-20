//
//  Purifier.swift
//  ReaderApp
//
//  替换净化：按规则删掉正文里的广告、网址、求票尾巴
//

import Foundation

/// 一条替换净化规则
struct PurifyRule: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var pattern: String
    var replacement: String
    var isRegex: Bool
    var enabled: Bool
    /// 只对章节标题生效
    var hitsTitle: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        pattern: String,
        replacement: String = "",
        isRegex: Bool = true,
        enabled: Bool = true,
        hitsTitle: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.enabled = enabled
        self.hitsTitle = hitsTitle
    }
}

/// 编译好的正则缓存，避免每章都重新编译
private final class RegexCache {
    static let shared = RegexCache()
    var map: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = map[pattern] { return cached }
        guard let built = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        map[pattern] = built
        return built
    }
}

enum Purifier {
    static let enabledKey = "purify.enabled"

    /// 总开关，默认开
    static var isOn: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 正文用哪些规则（排除只管标题的）
    static func bodyRules() -> [PurifyRule] {
        PurifierStore.shared.rules.filter { $0.enabled && $0.hitsTitle == false }
    }

    /// 标题用哪些规则
    static func titleRules() -> [PurifyRule] {
        PurifierStore.shared.rules.filter { $0.enabled && $0.hitsTitle }
    }

    static func clean(_ text: String) -> String {
        guard isOn, text.isEmpty == false else { return text }
        let rules = bodyRules()
        guard rules.isEmpty == false else { return text }
        return apply(rules, to: text)
    }

    static func cleanTitle(_ title: String) -> String {
        guard isOn else { return title }
        let rules = titleRules()
        guard rules.isEmpty == false else { return title }
        return apply(rules, to: title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 测试用：无视总开关，把所有启用的正文规则都跑一遍
    static func preview(_ text: String) -> String {
        apply(PurifierStore.shared.rules.filter { $0.enabled }, to: text)
    }

    static func apply(_ rules: [PurifyRule], to text: String) -> String {
        var result = text
        for rule in rules {
            result = apply(rule, to: result)
        }
        // 删掉整行后会留下连着的空行，压成一个
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }

    static func apply(_ rule: PurifyRule, to text: String) -> String {
        guard rule.pattern.isEmpty == false else { return text }
        if rule.isRegex {
            guard let regex = RegexCache.shared.regex(rule.pattern) else { return text }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: rule.replacement)
        }
        return text.replacingOccurrences(of: rule.pattern, with: rule.replacement)
    }

    /// 正则能不能编译，给编辑页做提示
    static func isValid(pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil
    }

    // MARK: - 推荐规则

    static var presets: [PurifyRule] {
        [
            PurifyRule(
                id: "preset.nextPage",
                name: "删「点击下一页继续阅读」",
                pattern: "本章未完\\s*[，,、]?\\s*(请)?(点击)?下一页继续阅读",
                replacement: ""
            ),
            PurifyRule(
                id: "preset.chapterEnd",
                name: "删「（本章完）」",
                pattern: "[（(【\\[]?\\s*本章完\\s*[）)】\\]]?",
                replacement: ""
            ),
            PurifyRule(
                id: "preset.urlLine",
                name: "删带网址的整行",
                pattern: "(?m)^[^\\n]*?(?:www\\.|https?://)[^\\n]*$",
                replacement: ""
            ),
            PurifyRule(
                id: "preset.voteLine",
                name: "删求票求收藏的整行",
                pattern: "(?m)^[^\\n]{0,60}(?:求收藏|求推荐票|求月票|求订阅|求打赏)[^\\n]{0,80}$",
                replacement: ""
            ),
            PurifyRule(
                id: "preset.bookTitleTail",
                name: "标题尾巴「最新章节」",
                pattern: "\\s*[（(【\\[]?\\s*(?:最新章节|全文阅读|免费阅读|无弹窗)\\s*[）)】\\]]?",
                replacement: "",
                hitsTitle: true
            )
        ]
    }
}

// MARK: - 规则仓库

final class PurifierStore: ObservableObject {
    static let shared = PurifierStore()

    @Published private(set) var rules: [PurifyRule] = []

    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("Purifiers.json")
        reload()
    }

    var activeCount: Int { rules.filter { $0.enabled }.count }

    /// 从磁盘重新读规则（恢复备份后调用）
    func reload() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PurifyRule].self, from: data),
              decoded.isEmpty == false else {
            rules = Purifier.presets
            return
        }
        rules = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func rule(with id: String) -> PurifyRule? {
        rules.first { $0.id == id }
    }

    func upsert(_ rule: PurifyRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        save()
    }

    func remove(_ id: String) {
        rules.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ id: String, _ value: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = value
        save()
    }

    func resetToPresets() {
        rules = Purifier.presets
        save()
    }
}
