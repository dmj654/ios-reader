//
//  DiscoverView.swift
//  ReaderApp
//
//  发现页：按书源分类 / 首页拉书单，不依赖关键词搜索。
//  - 书源在 Legado 里配了 exploreUrl 就出分类 chips；没配就拉首页推荐
//  - 书单规则缺省时回退搜索规则；点书进现有详情 / 在线阅读流程
//

import SwiftUI

struct DiscoverView: View {
    @ObservedObject var store: SourceStore
    var onSelect: (SourceItem) -> Void

    @State private var selectedSourceID: UUID?
    @State private var selectedLink: ExploreLink?
    @State private var items: [SourceItem] = []
    @State private var loading = false
    @State private var errorMessage: String?

    /// 可用源：启用、不是 JS 规则、有站点地址
    private var activeSources: [BookSource] {
        store.enabledSources.filter { $0.searchUnsupportedReason == nil && $0.baseUrl.isEmpty == false }
    }

    private var currentSource: BookSource? {
        activeSources.first { $0.id == selectedSourceID }
    }

    var body: some View {
        List {
            Section {
                if activeSources.isEmpty {
                    Text("没有可用的书源，先去书源管理导入")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeSources) { source in
                        Button {
                            selectSource(source)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(source.exploreLinks.isEmpty ? "首页推荐" : "\(source.exploreLinks.count) 个分类")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if source.id == selectedSourceID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("书源")
            }

            if let links = currentSource?.exploreLinks, links.isEmpty == false {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(links) { link in
                                Button {
                                    selectedLink = link
                                    load(link: link)
                                } label: {
                                    Text(link.title)
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            link == selectedLink
                                                ? Color.accentColor.opacity(0.15)
                                                : Color.secondary.opacity(0.12),
                                            in: Capsule()
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在加载书单…")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if items.isEmpty {
                    Text("选一个书源看推荐")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            row(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("书单 · \(items.count) 本")
            }
        }
        .listStyle(.plain)
        .onAppear {
            if selectedSourceID == nil, let first = activeSources.first {
                selectSource(first)
            }
        }
    }

    private func selectSource(_ source: BookSource) {
        selectedSourceID = source.id
        if let first = source.exploreLinks.first {
            selectedLink = first
            load(link: first)
        } else {
            selectedLink = nil
            loadHome(source: source)
        }
    }

    private func load(link: ExploreLink) {
        guard let source = currentSource else { return }
        Task { await loadItems(source: source, link: link) }
    }

    private func loadHome(source: BookSource) {
        Task { await loadItems(source: source, link: ExploreLink(title: "首页", url: source.baseUrl)) }
    }

    private func loadItems(source: BookSource, link: ExploreLink) async {
        loading = true
        errorMessage = nil
        do {
            items = try await SourceClient.discover(source: source, link: link)
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
        loading = false
    }

    private func row(for item: SourceItem) -> some View {
        HStack(spacing: 14) {
            cover(for: item)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.author.isEmpty ? "未知作者" : item.author)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.sourceName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Text(item.type.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func cover(for item: SourceItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if item.cover.isEmpty == false, let url = URL(string: item.cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.tertiary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: item.type == .comic ? "photo.on.rectangle" : "book.closed")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 76)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
