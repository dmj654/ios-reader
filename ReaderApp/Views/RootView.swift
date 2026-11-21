//
//  RootView.swift
//  ReaderApp
//
//  主界面：底部 主页 / 书架 / 发现 / 搜索 四段；设置从主页「…」进入。
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var shelf: BookshelfViewModel

    @StateObject private var settings = ReadingSettings()
    @StateObject private var sources = SourceStore.shared

    @State private var tab: RootTab = .home
    @State private var readerBook: Book?
    @State private var showSettings = false
    @State private var showHistory = false
    /// 发现 / 搜索共用的书详情弹层
    @State private var selectedSource: SourceItem?

    enum RootTab: Hashable {
        case home, shelf, discover, search
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(
                settings: settings,
                sources: sources,
                shelf: shelf,
                onOpenBook: { readerBook = $0 },
                onOpenSettings: { showSettings = true },
                switchTab: { tab = $0 },
                openHistory: { showHistory = true }
            )
            .tabItem {
                Label("主页", systemImage: "house")
            }
            .tag(RootTab.home)

            BookshelfView(settings: settings, sources: sources)
                .tabItem {
                    Label("书架", systemImage: "books.vertical")
                }
                .tag(RootTab.shelf)

            NavigationStack {
                DiscoverView(store: sources, onSelect: { selectedSource = $0 })
                    .navigationTitle("发现")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("发现", systemImage: "compass")
            }
            .tag(RootTab.discover)

            SourceSearchView(shelf: shelf, store: sources, onOpenBook: { book in
                readerBook = book
            }, embedded: true)
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(RootTab.search)
        }
        .fullScreenCover(item: $readerBook) { book in
            ReaderView(book: book, settings: settings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, sources: sources, books: shelf.books, shelf: shelf, embedded: true)
        }
        .sheet(item: $selectedSource) { item in
            NavigationStack {
                Group {
                    if let source = sources.sources.first(where: { $0.id == item.sourceID }) {
                        SourceBookView(item: item, source: source, shelf: shelf, store: sources) { book in
                            selectedSource = nil
                            readerBook = book
                        }
                    } else {
                        Text("书源已被删除")
                            .foregroundStyle(.secondary)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { selectedSource = nil }
                    }
                }
            }
        }
        .onAppear {
            // iCloud 启动时已把远端配置写盘，这里让各仓库重新读一次
            BackupStore.shared.reloadAllStores(shelf: shelf)
        }
    }
}
