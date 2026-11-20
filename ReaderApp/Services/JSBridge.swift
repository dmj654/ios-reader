//
//  JSBridge.swift
//  ReaderApp
//
//  第一阶段 JS 桥：用系统 JavaScriptCore 跑「表达式型」JS 规则。
//  上下文注入 result（当前取值）、baseUrl；java.ajax / org.jsoup 这类需要宿主
//  网络与 DOM 操作的绑定本机没实现，会明确判为不支持。
//

import Foundation
import JavaScriptCore

enum JSBridge {

    /// 脚本里有没有用到本机没实现的宿主绑定
    static func needsHostBinding(_ script: String) -> Bool {
        script.contains("java.ajax")
            || script.contains("org.jsoup")
            || script.contains("Jsoup.")
            || script.contains("cookieJar")
    }

    /// 从规则文本里抽出脚本（@js: 前缀或 <js> 块）；不是 JS 规则返回 nil
    static func script(in raw: String) -> String? {
        if raw.hasPrefix("@js:") {
            return String(raw.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let regex = try? NSRegularExpression(pattern: "(?is)<js>(.*?)</js>") else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 执行一段 JS，返回字符串结果；出错或空结果返回 nil
    static func evaluate(script: String, result: String, baseUrl: String) -> String? {
        guard let context = JSContext() else { return nil }

        var exception: String?
        context.exceptionHandler = { _, value in
            exception = value?.toString()
        }

        context.setObject(result, forKeyedSubscript: "result" as NSString)
        context.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        // Legado 里常见的别名，一并挂上
        context.evaluateScript("var book = { baseUrl: baseUrl }; var src = result;")

        let value = context.evaluateScript(script)
        if exception != nil { return nil }

        guard let out = value?.toString(), out.isEmpty == false else { return nil }
        return out
    }
}
