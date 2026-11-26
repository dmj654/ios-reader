//
//  RootView.swift
//  ReaderApp
//
//  主界面：今日 / 书架 / 发现 / 搜索 四段，底部换成悬浮毛玻璃导航。
//  - 系统 tab bar 隐藏，只保留四段分页行为
//  - 自绘 FloatingTabBar 叠在最上层，内容区留出玻璃高度
//  - 设置从今日页「…」进入
//

import SwiftUI

struct RootView: View {
    typealias RootTab = AppTab

    @EnvironmentObject var shelf: BookshelfViewModel

    @StateObject private var settings = ReadingSettings()
    @StateObject private var sources = SourceStore.shared

    @State private var tab: AppTab = .home
    @State private var readerBook: Book?
    @State private var showSettings = false
    @State private var showHistory = false
    /// 发现 / 搜索共用的书详情弹层
    @State private var selectedSource: SourceItem?

    var body: some View {
        ZStack(alignment: .bottom) {
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
                .background(AppTheme.background)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }
                .tag(AppTab.home)

                BookshelfView(settings: settings, sources: sources)
                    .background(AppTheme.background)
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(AppTab.shelf.title, systemImage: AppTab.shelf.symbol) }
                    .tag(AppTab.shelf)

                NavigationStack {
                    DiscoverView(store: sources, onSelect: { selectedSource = $0 })
                        .navigationTitle("发现")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.hidden, for: .tabBar)
                }
                .background(AppTheme.background)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label(AppTab.discover.title, systemImage: AppTab.discover.symbol) }
                .tag(AppTab.discover)

                SourceSearchView(shelf: shelf, store: sources, onOpenBook: { book in
                    readerBook = book
                }, embedded: true)
                .background(AppTheme.background)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label(AppTab.search.title, systemImage: AppTab.search.symbol) }
                .tag(AppTab.search)
            }
            .tint(AppTheme.accent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: AppTheme.tabBarReserve)
            }

            AmbientGlow()
                .frame(height: 230)
                .padding(.bottom, -40)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

            FloatingTabBar(tab: $tab)
        }
        .fullScreenCover(item: $readerBook) { book in
            ReaderView(book: book, settings: settings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, sources: sources, books: shelf.books, shelf: shelf)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(shelf: shelf, onOpenBook: { book in
                readerBook = book
            })
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
