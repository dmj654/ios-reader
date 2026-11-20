//
//  RootView.swift
//  ReaderApp
//
//  主界面：底部 书架 / 搜索 / 设置 三段
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var shelf: BookshelfViewModel

    @StateObject private var settings = ReadingSettings()
    @StateObject private var sources = SourceStore.shared

    @State private var tab: RootTab = .shelf
    @State private var readerBook: Book?

    enum RootTab: Hashable {
        case shelf, search, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            BookshelfView(settings: settings, sources: sources)
                .tabItem {
                    Label("书架", systemImage: "books.vertical")
                }
                .tag(RootTab.shelf)

            SourceSearchView(shelf: shelf, store: sources, onOpenBook: { book in
                readerBook = book
            }, embedded: true)
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(RootTab.search)

            SettingsView(settings: settings, sources: sources, books: shelf.books, shelf: shelf, embedded: true)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .fullScreenCover(item: $readerBook) { book in
            ReaderView(book: book, settings: settings)
        }
        .onAppear {
            // iCloud 启动时已把远端配置写盘，这里让各仓库重新读一次
            BackupStore.shared.reloadAllStores(shelf: shelf)
        }
    }
}
