//
//  ReaderApp.swift
//  ReaderApp
//
//  App 入口
//

import SwiftUI

@main
struct ReaderApp: App {
    @StateObject private var shelf = BookshelfViewModel()

    init() {
        // 自定义字体每次启动都要重新注册，否则读的是回退的系统字体
        _ = FontStore.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(shelf)
                .onOpenURL { url in
                    // 从「文件」App / 微信里点「用其他应用打开」时，直接导入
                    Task { _ = await shelf.importBook(from: url) }
                }
        }
    }
}
