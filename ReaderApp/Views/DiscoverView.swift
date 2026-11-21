//
//  DiscoverView.swift
//  ReaderApp
//
//  发现页（书城式）：顶部书源 / 分类横向 chips，下面封面墙浏览在线书目。
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

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sourceSection

                if let links = currentSource?.exploreLinks, links.isEmpty == false {
                    categorySection(links)
                }

                contentSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear {
            if selectedSourceID == nil, let first = activeSources.first {
                selectSource(first)
            }
        }
    }

    // MARK: - 书源 chips

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("书源")

            if activeSources.isEmpty {
                Text("没有可用的书源，先去设置 → 书源管理导入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeSources) { source in
                            sourceChip(source)
                        }
                    }
                }
            }
        }
    }

    private func sourceChip(_ source: BookSource) -> some View {
        let selected = source.id == selectedSourceID
        return Button {
            selectSource(source)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: source.type == .comic ? "photo.on.rectangle" : "book.closed")
                    .font(.system(size: 12, weight: .medium))
                Text(source.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
                in: Capsule()
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分类 chips

    private func categorySection(_ links: [ExploreLink]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("分类")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(links) { link in
                        Button {
                            selectedLink = link
                            load(link: link)
                        } label: {
                            Text(link.title)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    link == selectedLink
                                        ? Color.primary.opacity(0.88)
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(link == selectedLink ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 书单封面墙

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("书单 · \(items.count) 本")

            if loading {
                centeredState {
                    ProgressView()
                    Text("正在加载书单…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                centeredState {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else if items.isEmpty {
                centeredState {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选一个书源或分类看推荐")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        bookCard(item)
                    }
                }
            }
        }
    }

    private func bookCard(_ item: SourceItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover(for: item)

                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.author.isEmpty ? "未知作者" : item.author)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func centeredState<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                content()
            }
            .padding(.vertical, 50)
            Spacer()
        }
    }

    private func cover(for item: SourceItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if item.cover.isEmpty == false, let url = URL(string: item.cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderIcon(item)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                placeholderIcon(item)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func placeholderIcon(_ item: SourceItem) -> some View {
        Image(systemName: item.type == .comic ? "photo.on.rectangle" : "book.closed")
            .font(.system(size: 26))
            .foregroundStyle(.tertiary)
    }

    // MARK: - 数据加载

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
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
