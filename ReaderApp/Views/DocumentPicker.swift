//
//  DocumentPicker.swift
//  ReaderApp
//
//  文件选择器（v1.8.1）
//  - 不再套在 SwiftUI 的 .sheet 里，改成从「当前最上层 ViewController」直接 present
//    原因：iOS 18 上把 UIDocumentPickerViewController 塞进 .sheet，会出现
//    「选择器里一片空白」「选完文件不回调」「点打开没反应」这类问题。
//  - asCopy: true：系统先把文件拷到 App 沙盒，省掉 security-scoped 的坑
//  - 回调保证只在主线程发生一次（成功、取消、失败都走）
//

import UIKit
import UniformTypeIdentifiers

final class DocumentPickerHost: NSObject, UIDocumentPickerDelegate {

    /// 选择器只弱引用 delegate，必须在这里握住，否则会提前释放导致「选完没反应」
    private static var active: DocumentPickerHost?

    private let onPick: ([URL]) -> Void

    private init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
        super.init()
    }

    static func present(contentTypes: [UTType], allowsMultiple: Bool, onPick: @escaping ([URL]) -> Void) {
        guard let presenter = topViewController() else {
            onPick([])
            return
        }

        // 已经有一个在选择中，先别叠一个
        if active != nil { return }

        let host = DocumentPickerHost(onPick: onPick)
        active = host

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = host
        presenter.present(picker, animated: true)
    }

    /// 导出：把临时文件交给系统文件选择器，存到「文件」App 或其他位置
    static func presentExport(url: URL, onPick: @escaping ([URL]) -> Void) {
        guard let presenter = topViewController() else {
            onPick([])
            return
        }
        if active != nil { return }

        let host = DocumentPickerHost(onPick: onPick)
        active = host

        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = host
        presenter.present(picker, animated: true)
    }

    /// 从 key window 一路找最上层，注意可能是我们自己弹的 sheet
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return nil }

        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            // 弹出的选择器本身不要再往里钻
            if presented is UIDocumentPickerViewController { break }
            controller = presented
        }
        if controller is UIDocumentPickerViewController { return nil }
        return controller
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        complete(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        complete([])
    }

    private func complete(_ urls: [URL]) {
        let callback = onPick
        // 之后再放掉自己，保证本次调用期间对象还活着
        DispatchQueue.main.async {
            DocumentPickerHost.active = nil
        }
        callback(urls)
    }
}

// MARK: - 方便调用的类型集合

enum PickTypes {

    /// 书籍：给最宽的 .item，避免某些来源的文件在选择器里被灰掉点不动
    static var books: [UTType] {
        var types: [UTType] = [.item, .data, .content, .text, .pdf, .zip, .archive]
        for ext in ["epub", "cbz", "cbr", "txt", "text"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// 字体 ttf / otf / ttc
    static var fonts: [UTType] {
        var types: [UTType] = [.font, .item]
        for ext in ["ttf", "otf", "ttc"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// 备份包（zip 容器，扩展名 .readerbackup）
    static var backup: [UTType] {
        [.zip, .archive, .item, .data]
    }

    /// 书源 JSON
    static var json: [UTType] {
        var types: [UTType] = [.json, .plainText, .item]
        for ext in ["json", "txt", "legado"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
