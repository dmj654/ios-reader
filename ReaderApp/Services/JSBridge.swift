//
//  JSBridge.swift
//  ReaderApp
//
//  JS 规则桥：用系统 JavaScriptCore 跑 Legado 的 <js> / @js: 脚本。
//  第一阶段：纯表达式（result / baseUrl / book / src）。
//  第二阶段：宿主绑定——java.ajax（同步带 UA/Referer 请求）、java.put/get
//  临时变量罐、编码解码；org.jsoup DOM 绑定与 Cookie 罐仍未实现，会判为不支持。
//

import Foundation
import JavaScriptCore

enum JSBridge {

    /// 脚本里有没有用到本机还没实现的宿主绑定
    static func needsHostBinding(_ script: String) -> Bool {
        script.contains("org.jsoup")
            || script.contains("Jsoup.")
            || script.contains("cookieJar")
            || script.contains("java.getZipStringContent")
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

        // Legado 脚本里的临时变量罐：java.put("k", v) / java.get("k")
        let store = NSMutableDictionary()
        guard let java = JSValue(newObjectIn: context) else { return nil }

        let ajax: @convention(block) (JSValue, JSValue, JSValue) -> String = { urlArg, methodArg, bodyArg in
            let url = urlArg.toString() ?? ""
            let method = (methodArg.isUndefined || methodArg.isNull) ? "GET" : (methodArg.toString() ?? "GET")
            let body = (bodyArg.isUndefined || bodyArg.isNull) ? nil : bodyArg.toString()
            return syncFetch(url: url, method: method, body: body, referer: baseUrl)
        }

        let put: @convention(block) (String, JSValue) -> Void = { key, value in
            if let obj = value.toObject() { store[key] = obj }
        }

        let get: @convention(block) (String) -> Any = { key in
            (store[key] as Any)
        }

        let encodeURI: @convention(block) (String) -> String = {
            $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0
        }

        let decodeURI: @convention(block) (String) -> String = {
            $0.removingPercentEncoding ?? $0
        }

        let log: @convention(block) (JSValue) -> Void = { value in
            NSLog("[js] %@", value.toString() ?? "")
        }

        java.setObject(ajax, forKeyedSubscript: "ajax" as NSString)
        java.setObject(put, forKeyedSubscript: "put" as NSString)
        java.setObject(get, forKeyedSubscript: "get" as NSString)
        java.setObject(encodeURI, forKeyedSubscript: "encodeURI" as NSString)
        java.setObject(decodeURI, forKeyedSubscript: "decodeURI" as NSString)
        java.setObject(log, forKeyedSubscript: "log" as NSString)
        context.setObject(java, forKeyedSubscript: "java" as NSString)

        // Legado 里常见的别名，一并挂上
        context.evaluateScript("var book = { baseUrl: baseUrl }; var src = result;")

        let value = context.evaluateScript(script)
        if exception != nil { return nil }

        // 脚本最后可能把结果写进 result 变量，优先取返回值，其次取 result
        if let out = value?.toString(), out.isEmpty == false { return out }
        let resultValue = context.objectForKeyedSubscript("result")
        let resultText = resultValue.toString()
        if resultText.isEmpty == false { return resultText }
        return nil
    }

    // MARK: - 同步请求

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func syncFetch(url: String, method: String, body: String?, referer: String) -> String {
        guard let finalURL = URL(string: url) else { return "" }

        var request = URLRequest(url: finalURL)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if referer.isEmpty == false {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        if method.uppercased() == "POST" {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body?.data(using: .utf8)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result = ""

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                semaphore.signal()
                return
            }
            if let data, let text = TextLoader.decode(data) {
                result = text
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }
}
