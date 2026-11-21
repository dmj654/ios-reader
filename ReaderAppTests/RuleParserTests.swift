//
//  RuleParserTests.swift
//  ReaderAppTests
//
//  规则提取管线：用合成 HTML 验证列表节点、书名、链接、封面能正确取出并补全地址。
//

import XCTest
@testable import ReaderApp

final class RuleParserTests: XCTestCase {

    private let html = """
    <html><body>
      <ul class="book-list">
        <li>
          <a class="title" href="/book/1">斗罗之永恒斗罗</a>
          <span class="author">唐家三少</span>
          <img src="/cover/1.jpg">
        </li>
        <li>
          <a class="title" href="/book/2">斗破苍穹</a>
          <span class="author">天蚕土豆</span>
          <img src="/cover/2.jpg">
        </li>
      </ul>
    </body></html>
    """

    func testExtractBookListNodes() {
        guard let root = RuleParser.parseHTML(html) else {
            XCTFail("合成 HTML 应能解析")
            return
        }
        let nodes = RuleParser.nodes("css:ul.book-list li", in: root, base: "https://example.com/")
        XCTAssertEqual(nodes.count, 2)
    }

    func testExtractNameLinkAuthorCover() {
        guard let root = RuleParser.parseHTML(html) else {
            XCTFail("合成 HTML 应能解析")
            return
        }
        let nodes = RuleParser.nodes("css:ul.book-list li", in: root, base: "https://example.com/")
        let first = nodes[0]

        XCTAssertEqual(RuleParser.string("css:a.title@text", in: first, base: "https://example.com/"),
                       "斗罗之永恒斗罗")
        XCTAssertEqual(RuleParser.string("css:a.title@href", in: first, base: "https://example.com/"),
                       "https://example.com/book/1")
        XCTAssertEqual(RuleParser.string("css:span.author@text", in: first, base: "https://example.com/"),
                       "唐家三少")
        XCTAssertEqual(RuleParser.string("css:img@src", in: first, base: "https://example.com/"),
                       "https://example.com/cover/1.jpg")
    }

    func testAbsolutizeHandlesProtocolRelativeAndAbsolute() {
        XCTAssertEqual(
            RuleParser.absolutize("//cdn.example.com/a.png", base: "https://example.com/"),
            "https://cdn.example.com/a.png"
        )
        XCTAssertEqual(
            RuleParser.absolutize("https://other.com/b.png", base: "https://example.com/"),
            "https://other.com/b.png"
        )
    }
}
