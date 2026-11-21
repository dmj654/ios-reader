//
//  HomeView.swift
//  ReaderApp
//
//  主页（M1 骨架占位）：六张导航卡片的顺序与标题先固定下来，
//  M2 接个性化排序/显隐，M3 接真实摘要数据与跳转。
//

import SwiftUI

/// 主页占位卡片条目（标题、副标题、图标）
struct HomePlaceholder: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

struct HomeView: View {
    @ObservedObject var settings: ReadingSettings
    @ObservedObject var sources: SourceStore
    @ObservedObject var shelf: BookshelfViewModel

    var onOpenBook: (Book) -> Void
    var onOpenSettings: () -> Void

    /// PRD 3.2 定义的六张卡片默认顺序
    static let defaultPlaceholders: [HomePlaceholder] = [
        HomePlaceholder(id: "continue", title: "继续阅读", subtitle: "最近在读", icon: "bookmark"),
        HomePlaceholder(id: "local", title: "本地", subtitle: "导入的小说与漫画", icon: "folder"),
        HomePlaceholder(id: "history", title: "历史", subtitle: "读过的记录", icon: "clock"),
        HomePlaceholder(id: "sources", title: "在线书源", subtitle: "可用书源", icon: "list.bullet"),
        HomePlaceholder(id: "discover", title: "发现", subtitle: "书单与分类", icon: "compass"),
        HomePlaceholder(id: "search", title: "搜索", subtitle: "书名 / 作者", icon: "magnifyingglass")
    ]

    var body: some View {
        NavigationStack {
            List(Self.defaultPlaceholders) { item in
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .frame(width: 30)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .medium))
                        Text(item.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}
