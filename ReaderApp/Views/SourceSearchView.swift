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
    @State private var showCheck = false
    @State private var selected: SourceItem?
    @State private var filter: SourceFilter = .all

    @AppStorage("sourceSearchKeyword") private var storedKeyword = ""
    @AppStorage("sourceSearchFilter") private var storedFilter = SourceFilter.all.rawValue
    /// 一次搜索最多动用多少个源（一千条源全发出去等于全超时）
    @AppStorage("sourceSearchLimit") private var searchLimit = 30

    /// 当前分类下真正能用的源（排掉规则残缺和只能靠 JS 的，它们必然搜不到）
    private var activeSources: [BookSource] {
        let enabled = store.enabledSources
        let base = filter.type == nil ? enabled : enabled.filter { $0.type == filter.type }
        return base.filter { $0.searchUnsupportedReason == nil }
    }

    /// 这次实际会搜多少个源
    private var effectiveCount: Int {
        min(activeSources.count, max(1, searchLimit))
    }

    /// 开着但规则不完整 / 缺 JS 引擎、没参与搜索的源
    private var incompleteNotes: [String] {
        let scoped = store.sources.filter { $0.enabled && (filter.type == nil || $0.type == filter.type) }
        return scoped
            .filter { $0.baseUrl.isEmpty || $0.search.list.isEmpty || $0.searchUnsupportedReason != nil }
            .map { source -> String in
                if let js = source.searchUnsupportedReason {
                    return "「\(source.name)」用了 JS 规则（\(js)），本机没有 JS 引擎，没参与搜索"
                }
                return "「\(source.name)」规则不完整（\(SourceStore.problems(for: source).joined(separator: "、"))，没参与搜索"
            }
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
                    storedKeyword = vm.keyword
                    Task { await vm.search(sources: activeSources, limit: searchLimit, store: store) }
                }
                .onAppear {
                    if vm.keyword.isEmpty, storedKeyword.isEmpty == false {
                        vm.keyword = storedKeyword
                    }
                    if let restored = SourceFilter(rawValue: storedFilter), filter != restored {
                        filter = restored
                    }
                }
                .onChange(of: filter) { _, newValue in
                    storedFilter = newValue.rawValue
                    vm.results = []
                    vm.errorMessage = nil
                    vm.failures = []
                    vm.failureBuckets = []
                    vm.searchedCount = 0
                    vm.plannedCount = 0
                }
                .sheet(isPresented: $showManager) {
                    SourceManagerView(store: store)
                }
                .sheet(isPresented: $showCheck) {
                    SourceCheckView(store: store)
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
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(SourceFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Picker("一次搜几个源", selection: $searchLimit) {
                        Text("30 个").tag(30)
                        Text("60 个").tag(60)
                        Text("100 个").tag(100)
                        Text("全部").tag(9999)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "dial.medium")
                        Text("\(effectiveCount)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                Text("共 \(activeSources.count) 个可用源，按「以前搜成功过」优先取 \(effectiveCount) 个")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if vm.searching && vm.results.isEmpty {
            searchingPlaceholder
        } else if vm.results.isEmpty {
            placeholder
        } else {
            resultList
        }
    }

    private var searchingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("正在搜索 \(vm.searchedCount) / \(vm.plannedCount) 个源…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if vm.results.isEmpty == false {
                Text("已经找到 \(vm.results.count) 本")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            Button(role: .destructive) {
                vm.cancelSearch()
            } label: {
                Text("停止")
                    .font(.footnote)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }
            .padding(.top, 4)

            Text("每次只并发 6 个、每个最多等 12 秒，搜完一批就先出结果。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text("共 \(activeSources.count) 个可用\(filter == .all ? "" : filter.title)源，这次会搜 \(effectiveCount) 个（按以前搜成功过优先）")
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

                if vm.errorMessage != nil || activeSources.isEmpty == false {
                    VStack(spacing: 6) {
                        Button {
                            showCheck = true
                        } label: {
                            Label("书源体检（找出哪些源真能搜到书）", systemImage: "stethoscope")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Text("一次测几十个源，直接告诉你哪些能用、哪些连不上，不用一千条一条条试。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
    }

    private var resultList: some View {
        List {
            if vm.searching {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("搜 \(vm.searchedCount) / \(vm.plannedCount) 个源，已命中 \(vm.results.count) 本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Button("停止") { vm.cancelSearch() }
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.failureBuckets.isEmpty == false || incompleteNotes.isEmpty == false {
                Section {
                    ForEach(vm.failureBuckets) { bucket in
                        HStack(spacing: 8) {
                            Text("×\(bucket.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.reason)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Text("例如「\(bucket.sample)」")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if vm.failures.isEmpty == false {
                        DisclosureGroup("明细（前 \(vm.failures.count) 条）") {
                            ForEach(Array(vm.failures.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    ForEach(Array(incompleteNotes.prefix(4).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if incompleteNotes.count > 4 {
                        Text("还有 \(incompleteNotes.count - 4) 个源规则不完整，去书源管理看")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        showManager = true
                    } label: {
                        Label("去书源管理检查", systemImage: "globe")
                            .font(.caption)
                    }
                } header: {
                    Text("没出结果的源")
                } footer: {
                    Text("同一个原因合并成一条；「网络超时」多半是站点被墙或连不上，「403」是站点要 Cookie 或拦了非浏览器请求。")
                }
            }

            Section {
                ForEach(vm.results) { item in
                    Button {
                        selected = item
                    } label: {
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
                    .buttonStyle(.plain)
                }
            } header: {
                Text("共 \(vm.results.count) 条结果")
            } footer: {
                Text("点进去可以直接在线阅读，不用先下载。")
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
        .frame(width: 56, height: 76)
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
    @State private var reading = false
    @State private var startIndex = 0

    private var limitOptions: [(title: String, value: Int)] {
        switch item.type {
        case .novel:
            return [("整本", 0), ("前 50 章", 50), ("前 10 章", 10)]
        case .comic:
            return [("整本", 0), ("前 10 章", 10), ("前 3 章", 3)]
        }
    }

    /// 上次读到第几章
    private var savedIndex: Int {
        let value = UserDefaults.standard.integer(forKey: "readpos-\(item.link)")
        guard vm.chapters.isEmpty == false else { return 0 }
        return max(0, min(value, vm.chapters.count - 1))
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    cover(size: CGSize(width: 92, height: 126))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 19, weight: .semibold))
                            .lineLimit(2)
                        Text(item.author.isEmpty ? "未知作者" : item.author)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(source.name)
                                .lineLimit(1)
                            Text("·")
                            Text(item.type.title)
                            if vm.chaptersLoading == false && vm.chapters.isEmpty == false {
                                Text("·")
                                Text("\(vm.chapters.count) 章")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    startIndex = savedIndex
                    reading = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                        Text(savedIndex > 0 ? "继续阅读 · 第 \(savedIndex + 1) 章" : "开始阅读")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(vm.chapters.isEmpty)

                if vm.chaptersLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在取目录…").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error = vm.chapterError {
                    Text("目录没取到：\(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("点章节或上面的按钮直接在线看，正文会预载后两章，翻章不用等。")
            }

            Section {
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
                Text("下载到本地（不下载也能直接在线看）")
            }

            if vm.chapters.isEmpty == false {
                Section {
                    ForEach(vm.chapters.prefix(300).indices, id: \.self) { index in
                        Button {
                            startIndex = index
                            reading = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                                Text(vm.chapters[index].name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
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
        .fullScreenCover(isPresented: $reading) {
            SourceReaderView(
                source: source,
                item: item,
                chapters: vm.chapters,
                startIndex: startIndex
            )
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

    private func cover(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if item.cover.isEmpty == false, let url = URL(string: item.cover) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.tertiary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: item.type == .comic ? "photo.on.rectangle" : "book.closed")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
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
