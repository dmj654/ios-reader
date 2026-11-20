//
//  FontLibrary.swift
//  ReaderApp
//
//  自定义字体：把 ttf / otf 拷进 Documents/Fonts，启动时注册，阅读页按名字取。
//

import UIKit
import CoreText
import SwiftUI

enum FontLibrary {

    struct Item: Identifiable, Hashable {
        /// PostScript 名，UIFont(name:size:) 用的是这个
        let id: String
        let displayName: String
        let fileName: String
    }

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Fonts", isDirectory: true)
    }

    /// 启动时调用一次：把已经拷进来的字体重注册一遍（App 重启后注册会失效）
    static func registerInstalled() {
        for item in installed() where UIFont(name: item.id, size: 16) == nil {
            let url = folder.appendingPathComponent(item.fileName)
            register(url)
        }
    }

    static func installed() -> [Item] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var items: [Item] = []
        for name in names.sorted() {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ["ttf", "otf", "ttc"].contains(ext) else { continue }
            let url = folder.appendingPathComponent(name)
            guard let postScript = postScriptName(of: url) else { continue }
            let display = fullName(of: url) ?? postScript
            items.append(Item(id: postScript, displayName: display, fileName: name))
        }
        return items
    }

    /// 安装一个字体文件，返回 PostScript 名
    static func install(from url: URL) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let name = url.lastPathComponent
        let target = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)

        guard register(target) else {
            throw FontError.unreadable
        }
        guard let postScript = postScriptName(of: target), UIFont(name: postScript, size: 16) != nil else {
            throw FontError.unreadable
        }
        return postScript
    }

    static func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(item.fileName))
    }

    // MARK: - 取字体

    static func uiFont(name: String?, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if let name, let font = UIFont(name: name, size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func font(name: String?, size: CGFloat) -> Font {
        if let name, UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        return Font.system(size: size)
    }

    // MARK: - 底层

    enum FontError: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "这个字体文件读不出来（只支持 ttf / otf / ttc）"
        }
    }

    @discardableResult
    private static func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if ok { return true }
        // 已经注册过也算成功
        if let error = error?.takeRetainedValue(),
           CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue {
            return true
        }
        return false
    }

    private static func postScriptName(of url: URL) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let name = font.postScriptName else { return nil }
        return name as String
    }

    private static func fullName(of url: URL) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let name = font.fullName else { return nil }
        return name as String
    }
}

// MARK: - 给界面用的小仓库

final class FontStore: ObservableObject {
    static let shared = FontStore()

    @Published private(set) var items: [FontLibrary.Item] = []

    private init() {
        refresh()
    }

    func refresh() {
        FontLibrary.registerInstalled()
        items = FontLibrary.installed()
    }

    /// 返回 nil 表示成功，否则是错误说明
    func add(_ url: URL) -> String? {
        do {
            let postScript = try FontLibrary.install(from: url)
            refresh()
            return "已导入字体「\(displayName(for: postScript))」"
        } catch {
            return error.localizedDescription
        }
    }

    func remove(_ item: FontLibrary.Item) {
        FontLibrary.remove(item)
        refresh()
    }

    private func displayName(for postScript: String) -> String {
        items.first { $0.id == postScript }?.displayName ?? postScript
    }
}
