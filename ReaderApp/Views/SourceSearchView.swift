//
//  SourceSearchView.swift
//  ReaderApp
//
//  找书：按书源并发搜索 → 打开详情 → 整本下载成 TXT / CBZ 入书架
//

import SwiftUI

enum SourceFilter: String, CaseIterable, Identifiable {
    case all, novel, comic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .novel: return "小说"
        case .comic: return "漫画"
        }
    }

    var type: SourceType? {
        switch self {
        case .all: return nil
        case .novel: return .novel
        case .comic: return .comic
        }
    }
}

struct SourceSearchView: View {
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject var store: SourceStore
    var onOpenBook: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SourceViewModel()
    @State private var showManager = false
    @State private var selected: SourceItem?
    @State private var filter: SourceFilter = .all

    /// 当前分类下真正能用的源
    private var activeSources: [BookSource] {
        let enabled = store.enabledSources
        guard let type = filter.type else { return enabled }
        return enabled.filter { $0.type == type }
    }

    /// 开着但规则不完整、没参与搜索的源
    private var incompleteNotes: [String] {
        store.sources
            .filter { $0.enabled && (filter.type == nil || $0.type == filter.type) }
            .filter { $0.baseUrl.isEmpty || $0.search.list.isEmpty }
            .map { "「\($0.name)」规则不完整（\(SourceStore.problems(for: $0).joined(separator: "、"))），没参与搜索" }
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    filterBar
                }
                .navigationTitle("找书")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showManager = true
                        } label: {
                            Image(systemName: "globe")
                        }
                    }
                }
                .searchable(
                    text: $vm.keyword,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: filter == .comic ? "漫画名 / 作者，回车搜索" : "书名 / 作者，回车搜索"
                )
                .onSubmit(of: .search) {
                    Task { await vm.search(sources: activeSources) }
                }
                .onChange(of: filter) { _, _ in
                    vm.results = []
                    vm.errorMessage = nil
                }
                .sheet(isPresented: $showManager) {
                    SourceManagerView(store: store)
                }
                .navigationDestination(item: $selected) { item in
                    if let source = store.sources.first(where: { $0.id == item.sourceID }) {
                        SourceBookView(item: item, source: source, shelf: shelf) { book in
                            dismiss()
                            onOpenBook(book)
                        }
                    } else {
                        Text("书源已被删除")
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var filterBar: some View {
        Picker("", selection: $filter) {
            ForEach(SourceFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if vm.searching {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在搜索 \(activeSources.count) 个\(filter == .all ? "" : filter.title + "源")…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            placeholder
        } else {
            resultList
        }
    }

    private var placeholder: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: filter == .comic ? "photo.on.rectangle" : "magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 50)

                Text("输入书名或作者后回车")
                    .font(.title3.weight(.medium))

                if activeSources.isEmpty {
                    Text(filter == .comic ? "现在没有启用的漫画源" : "现在没有启用的小说源")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("打开书源管理") { showManager = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                    Text("小说源和漫画源是分开管的，别把漫画源的规则填在小说源里。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                } else {
                    Text("会用 \(activeSources.map(\.name).joined(separator: "、")) 去搜")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                if incompleteNotes.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(incompleteNotes.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
    }

    private var resultList: some View {
        List {
            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.failures.isEmpty == false || incompleteNotes.isEmpty == false {
                Section {
                    ForEach(Array(vm.failures.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(incompleteNotes.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showManager = true
                    } label: {
                        Label("去书源管理检查", systemImage: "globe")
                            .font(.caption)
                    }
                } header: {
                    Text("没出结果的源")
                }
            }

            Section {
                ForEach(vm.results) { item in
                    Button {
                        selected = item
                    } label: {
                        HStack(spacing: 12) {
                            cover(for: item)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Text(item.author.isEmpty ? "未知作者" : item.author)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(item.sourceName)
                                    Text("·")
                                    Text(item.type.title)
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("共 \(vm.results.count) 条结果")
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
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
        .frame(width: 42, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - 书详情 / 下载

struct SourceBookView: View {
    let item: SourceItem
    let source: BookSource
    @ObservedObject var shelf: BookshelfViewModel
    var onOpenBook: (Book) -> Void

    @StateObject private var vm = SourceViewModel()
    @State private var limitIndex = 0
    @State private var alertText: String?

    private var limitOptions: [(title: String, value: Int)] {
        switch item.type {
        case .novel:
            return [("整本", 0), ("前 50 章", 50), ("前 10 章", 10)]
        case .comic:
            return [("整本", 0), ("前 10 章", 10), ("前 3 章", 3)]
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 20, weight: .semibold))
                    Text(item.author.isEmpty ? "未知作者" : item.author)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(source.name) · \(item.type.title)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            Section {
                if vm.chaptersLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在取目录…").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error = vm.chapterError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("共 \(vm.chapters.count) 章")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker("下载范围", selection: $limitIndex) {
                    ForEach(limitOptions.indices, id: \.self) { index in
                        Text(limitOptions[index].title).tag(index)
                    }
                }
                .pickerStyle(.segmented)

                if vm.downloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: vm.progress)
                        Text(vm.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        Task { await startDownload() }
                    } label: {
                        Label(
                            item.type == .comic ? "下载到书架（打包成 CBZ）" : "下载到书架",
                            systemImage: "arrow.down.circle"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(vm.chapters.isEmpty)
                }
            } header: {
                Text("下载")
            }

            if vm.chapters.isEmpty == false {
                Section {
                    ForEach(vm.chapters.prefix(300).indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 30, alignment: .trailing)
                            Text(vm.chapters[index].name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                    }
                    if vm.chapters.count > 300 {
                        Text("还有 \(vm.chapters.count - 300) 章未显示")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("目录")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm.chapters.isEmpty { await vm.loadChapters(source: source, item: item) }
        }
        .alert("提示", isPresented: Binding(
            get: { alertText != nil },
            set: { if $0 == false { alertText = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
    }

    private func startDownload() async {
        let limit = limitOptions[min(limitIndex, limitOptions.count - 1)].value
        let book = await vm.download(source: source, item: item, limit: limit, shelf: shelf)
        if let book {
            onOpenBook(book)
        } else {
            alertText = vm.finishedMessage ?? "下载失败"
        }
    }
}
