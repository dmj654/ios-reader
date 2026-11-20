//
//  BookSource.swift
//  ReaderApp
//
//  书源（小说源 / 漫画源）：一套 JSON 规则，描述「怎么搜、怎么取目录、怎么取正文」
//  设计目标：字段少、能手写、能自己改，不依赖 JS 引擎。
//

import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case novel
    case comic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novel: return "小说"
        case .comic: return "漫画"
        }
    }
}

// MARK: - 三条规则

struct SearchRule: Codable, Hashable {
    var url: String = ""
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: String?
    var list: String = ""
    var name: String = ""
    var author: String = ""
    var cover: String = ""
    var link: String = ""

    init(url: String = "", method: String = "GET", headers: [String: String] = [:], body: String? = nil,
         list: String = "", name: String = "", author: String = "", cover: String = "", link: String = "") {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.list = list
        self.name = name
        self.author = author
        self.cover = cover
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try c.decodeIfPresent(String.self, forKey: .body)
        list = try c.decodeIfPresent(String.self, forKey: .list) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
    }
}

struct ChapterRule: Codable, Hashable {
    var url: String = "{{link}}"
    var list: String = ""
    var name: String = ""
    var link: String = ""

    init(url: String = "{{link}}", list: String = "", name: String = "", link: String = "") {
        self.url = url
        self.list = list
        self.name = name
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? "{{link}}"
        list = try c.decodeIfPresent(String.self, forKey: .list) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
    }
}

struct ContentRule: Codable, Hashable {
    var url: String = "{{link}}"
    /// 小说正文
    var text: String = ""
    /// 漫画图片列表（一组 img 节点，取 @src）
    var images: String = ""
    /// 取正文前先删掉的节点（广告、推荐块）
    var remove: [String] = []
    /// 逐行过滤的正则（去掉「请记住本站」这类行）
    var removeLines: [String] = []

    init(url: String = "{{link}}", text: String = "", images: String = "",
         remove: [String] = [], removeLines: [String] = []) {
        self.url = url
        self.text = text
        self.images = images
        self.remove = remove
        self.removeLines = removeLines
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? "{{link}}"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        images = try c.decodeIfPresent(String.self, forKey: .images) ?? ""
        remove = try c.decodeIfPresent([String].self, forKey: .remove) ?? []
        removeLines = try c.decodeIfPresent([String].self, forKey: .removeLines) ?? []
    }
}

// MARK: - 书源

struct BookSource: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "新书源"
    var type: SourceType = .novel
    /// 站点根地址，所有相对链接和图片都以它为基准
    var baseUrl: String = ""
    /// 所有请求都带上的头（Legado 书源里的 header，常放 UA / Cookie）
    var headers: [String: String] = [:]
    var enabled: Bool = true
    var search: SearchRule = SearchRule()
    var chapters: ChapterRule = ChapterRule()
    var content: ContentRule = ContentRule()
    /// Legado 的 bookSourceGroup（多个组用逗号隔开，这里取第一个）
    var group: String?
    /// 搜索成功次数（用来把能用的源排前面）
    var successCount: Int = 0
    /// 搜索失败次数
    var failCount: Int = 0
    var lastSuccessAt: Date?
    var lastUsedAt: Date?

    init() {}
    init(name: String, type: SourceType, baseUrl: String,
         search: SearchRule, chapters: ChapterRule, content: ContentRule,
         headers: [String: String] = [:]) {
        self.name = name
        self.type = type
        self.baseUrl = baseUrl
        self.headers = headers
        self.search = search
        self.chapters = chapters
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, baseUrl, headers, enabled, search, chapters, content
        case group, successCount, failCount, lastSuccessAt, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名书源"
        type = try c.decodeIfPresent(SourceType.self, forKey: .type) ?? .novel
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        search = try c.decodeIfPresent(SearchRule.self, forKey: .search) ?? SearchRule()
        chapters = try c.decodeIfPresent(ChapterRule.self, forKey: .chapters) ?? ChapterRule()
        content = try c.decodeIfPresent(ContentRule.self, forKey: .content) ?? ContentRule()
        group = try c.decodeIfPresent(String.self, forKey: .group)
        successCount = try c.decodeIfPresent(Int.self, forKey: .successCount) ?? 0
        failCount = try c.decodeIfPresent(Int.self, forKey: .failCount) ?? 0
        lastSuccessAt = try c.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    /// 供编辑界面用的格式化 JSON
    func prettyJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: 新建模板（模型）

    static let novelTemplate = BookSource(
        name: "新小说源",
        type: .novel,
        baseUrl: "",
        search: SearchRule(
            url: "/search.php?q={{key}}&page={{page}}",
            list: "css:ul.book-list li",
            name: "css:a.title@text",
            author: "css:span.author@text",
            cover: "css:img@src",
            link: "css:a.title@href"
        ),
        chapters: ChapterRule(
            url: "{{link}}",
            list: "css:#chapterlist li",
            name: "css:a@text",
            link: "css:a@href"
        ),
        content: ContentRule(
            url: "{{link}}",
            text: "css:#content@text",
            remove: ["css:.ad", "css:script", "css:style"],
            removeLines: ["请记住本站", "^章节错误.*$"]
        )
    )

    static let comicTemplate = BookSource(
        name: "新漫画源",
        type: .comic,
        baseUrl: "",
        search: SearchRule(
            url: "/search.php?q={{key}}&page={{page}}",
            list: "css:ul.book-list li",
            name: "css:a.title@text",
            author: "css:span.author@text",
            cover: "css:img@src",
            link: "css:a.title@href"
        ),
        chapters: ChapterRule(
            url: "{{link}}",
            list: "css:#chapterlist li",
            name: "css:a@text",
            link: "css:a@href"
        ),
        content: ContentRule(
            url: "{{link}}",
            text: "",
            images: "css:#images img@src"
        )
    )

    // MARK: 示例

    static let template = """
    {
      "name": "我的书源",
      "type": "novel",
      "baseUrl": "https://www.example.com",
      "enabled": true,
      "search": {
        "url": "/search.php?q={{key}}&page={{page}}",
        "method": "GET",
        "list": "css:ul.book-list li",
        "name": "css:a.title@text",
        "author": "css:span.author@text",
        "cover": "css:img@src",
        "link": "css:a.title@href"
      },
      "chapters": {
        "url": "{{link}}",
        "list": "css:#chapterlist li",
        "name": "css:a@text",
        "link": "css:a@href"
      },
      "content": {
        "url": "{{link}}",
        "text": "css:#content@text",
        "remove": ["css:.ad", "css:script"],
        "removeLines": ["请记住本站", "^章节错误.*$"]
      }
    }
    """

    /// 规则里有没有本机引擎做不到的东西（JS）。
    /// 这里只做字符串判断——一千条源在列表里每帧都要算，不能跑解析器
    var searchUnsupportedReason: String? {
        for raw in [search.url, search.body ?? "", search.list, search.name, search.link, search.cover] {
            if raw.contains("<js>") || raw.contains("@js:") { return "JS 规则" }
        }
        return nil
    }
}

// MARK: - 网络结果

struct SourceItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var author: String
    var cover: String
    var link: String
    var sourceID: UUID
    var sourceName: String
    var type: SourceType
    var intro: String = ""
    var status: String = ""
    var wordCount: String = ""
    var latestChapter: String = ""
}

struct SourceChapter: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var link: String
}

/// 详情页顺带抓到的书信息（简介 / 状态 / 字数 / 最新章）
struct BookMeta: Hashable {
    var intro: String = ""
    var status: String = ""
    var wordCount: String = ""
    var latestChapter: String = ""
}

struct BookDetail: Hashable {
    var chapters: [SourceChapter]
    var meta: BookMeta
}
