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

    var body: some Scene {
        WindowGroup {
            BookshelfView()
                .environmentObject(shelf)
                .onOpenURL { url in
                    // 从「文件」App 里点「用其他应用打开」时，直接导入
                    shelf.importBook(from: url)
                }
        }
    }
}
