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
    /// 作为底部「搜索」tab 常驻时没有可以 dismiss 的 sheet，就不要显示「关闭」
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SourceViewModel()
    @State private var showManager = false
    @State private var showCheck = false
    @State private var showSkipped = false
    @State private var selected: SourceItem?
    @State private var filter: SourceFilter = .all

    /// 结果筛选：作者名 + 仅精确匹配书名
    @State private var authorFilter = ""
    @AppStorage("search.exactOnly") private var exactOnly = false

    @AppStorage("sourceSearchKeyword") private var storedKeyword = ""
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "sourceSearchHistory") ?? []
    @AppStorage("sourceSearchFilter") private var storedFilter = SourceFilter.all.rawValue
    /// 一次搜索最多动用多少个源（一千条源全发出去等于全超时）
    @AppStorage("sourceSearchLimit") private var searchLimit = 30

    /// 当前分类下真正能用的源（缓存：只在书源列表 / 分类变化时重算，避免打字时反复过滤上千条）
    @State private var usableSources: [BookSource] = []
    @State private var skippedCount = 0

    private var activeSources: [BookSource] { usableSources }

    /// 这次实际会搜多少个源
    private var effectiveCount: Int {
        min(usableSources.count, max(1, searchLimit))
    }

    private func recomputeSourceLists() {
        let scoped = store.sources.filter { $0.enabled && (filter.type == nil || $0.type == filter.type) }
        let usable = scoped.filter { $0.searchUnsupportedReason == nil }
        usableSources = usable
        skippedCount = scoped.count - usable.count
    }

    /// 按作者名 / 精确匹配过滤后的结果
    private var visibleResults: [SourceItem] {
        let keyword = vm.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = authorFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return vm.results.filter { item in
            if exactOnly, Self.normalized(item.name) != Self.normalized(keyword) { return false }
            if author.isEmpty == false, item.author.localizedCaseInsensitiveContains(author) == false { return false }
            return true
        }
    }

    private static func normalized(_ raw: String) -> String {
        var out = ""
        for character in raw.lowercased() where character.isLetter || character.isNumber {
            out.append(character)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            searchContent
                .searchable(
                    text: $vm.keyword,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: filter == .comic ? "漫画名 / 作者，回车搜索" : "书名 / 作者，回车搜索"
                )
                .onSubmit(of: .search) {
                    Task { await runSearch() }
                }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .navigationTitle("找书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if embedded == false {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showManager = true
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
                .onAppear {
                    if vm.keyword.isEmpty, storedKeyword.isEmpty == false {
                        vm.keyword = storedKeyword
                    }
                    if let restored = SourceFilter(rawValue: storedFilter), filter != restored {
                        filter = restored
                    }
                    recomputeSourceLists()
                }
                .onChange(of: filter) { _, newValue in
                    storedFilter = newValue.rawValue
                    vm.results = []
                    vm.errorMessage = nil
                    vm.failures = []
                    vm.failureBuckets = []
                    vm.searchedCount = 0
                    vm.plannedCount = 0
                    recomputeSourceLists()
                }
                .onChange(of: store.sources) { _, _ in
                    recomputeSourceLists()
                }
                .sheet(isPresented: $showManager) {
                    SourceManagerView(store: store)
                }
                .sheet(isPresented: $showCheck) {
                    SourceCheckView(store: store)
                }
                .sheet(isPresented: $showSkipped) {
                    SourceSkippedView(store: store)
                }
                .navigationDestination(item: $selected) { item in
                    if let source = store.sources.first(where: { $0.id == item.sourceID }) {
                        SourceBookView(item: item, source: source, shelf: shelf, store: store) { book in
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
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var searchContent: some View {
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
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: filter == .comic ? "photo.on.rectangle" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            if activeSources.isEmpty {
                Text(filter == .comic ? "没有启用的漫画源" : "没有启用的小说源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("去书源管理") { showManager = true }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
            } else {
                Text("输入书名或作者，回车搜索")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(activeSources.count) 个源可用 · 本次搜 \(effectiveCount) 个")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            if skippedCount > 0 {
                Button {
                    showSkipped = true
                } label: {
                    HStack(spacing: 4) {
                        Text("跳过 \(skippedCount) 个用不了的源")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.1), in: Capsule())
                }
                .padding(.top, 2)
            }

            if history.isEmpty == false, vm.keyword.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("最近搜过")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Button("清空") {
                            history = []
                            UserDefaults.standard.removeObject(forKey: "sourceSearchHistory")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(history, id: \.self) { word in
                                Button {
                                    vm.keyword = word
                                    Task { await runSearch() }
                                } label: {
                                    Text(word)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.secondary.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 10)
            }

            Button {
                showCheck = true
            } label: {
                Label("书源体检", systemImage: "stethoscope")
                    .font(.system(size: 12))
            }
            .padding(.top, 4)

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() async {
        let word = vm.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.isEmpty == false else { return }
        storedKeyword = word
        remember(word)
        await vm.search(sources: activeSources, limit: searchLimit, store: store)
    }

    /// 最近搜过的关键词，最多 8 个，搜过的排最前
    private func remember(_ word: String) {
        var list = history
        list.removeAll { $0 == word }
        list.insert(word, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        history = list
        UserDefaults.standard.set(list, forKey: "sourceSearchHistory")
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

            if vm.failureBuckets.isEmpty == false || skippedCount > 0 {
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

                    if skippedCount > 0 {
                        Button {
                            showSkipped = true
                        } label: {
                            HStack(spacing: 5) {
                                Text("另有 \(skippedCount) 个源规则用不了（JS / 缺字段），已跳过")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
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
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    TextField("按作者名筛选", text: $authorFilter)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        exactOnly.toggle()
                    } label: {
                        Text(exactOnly ? "精确 · 开" : "精确")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(exactOnly ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(visibleResults) { item in
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
                Text("共 \(visibleResults.count) 条结果")
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

// MARK: - 用不了的源清单

struct SourceSkippedView: View {
    @ObservedObject var store: SourceStore
    @Environment(\.dismiss) private var dismiss

    private var jsSources: [BookSource] {
        store.sources.filter { $0.enabled && $0.searchUnsupportedReason != nil }
    }

    private var brokenSources: [BookSource] {
        store.sources.filter {
            $0.enabled && $0.searchUnsupportedReason == nil && ($0.baseUrl.isEmpty || $0.search.list.isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if jsSources.isEmpty == false {
                    Section {
                        ForEach(jsSources.prefix(60)) { source in
                            Text(source.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        if jsSources.count > 60 {
                            Text("还有 \(jsSources.count - 60) 个，同理")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Button(role: .destructive) {
                            store.setEnabled(ids: Set(jsSources.map(\.id)), enabled: false)
                            store.flushPendingSave()
                            dismiss()
                        } label: {
                            Label("把这 \(jsSources.count) 个停用", systemImage: "pause.circle")
                                .font(.system(size: 13))
                        }
                    } header: {
                        Text("JS 规则 · \(jsSources.count) 个")
                    } footer: {
                        Text("搜索地址或规则里带了 <js> 脚本。本机没有 JS 引擎，这类源永远搜不到，建议直接停用。")
                    }
                }

                if brokenSources.isEmpty == false {
                    Section {
                        ForEach(brokenSources.prefix(60)) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text("缺 \(SourceStore.problems(for: source).joined(separator: "、"))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        Text("规则不完整 · \(brokenSources.count) 个")
                    } footer: {
                        Text("没填站点地址或搜索列表规则，改好规则才能用。")
                    }
                }
            }
            .navigationTitle("用不了的源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 书详情 / 下载

struct SourceBookView: View {
    @State private var item: SourceItem
    @State private var source: BookSource
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject var store: SourceStore
    var onOpenBook: (Book) -> Void

    @StateObject private var vm = SourceViewModel()
    @State private var limitIndex = 0
    @State private var alertText: String?
    @State private var reading = false
    @State private var startIndex = 0

    @State private var showSwitch = false
    @State private var switching = false
    @State private var alternates: [Alternate] = []

    @StateObject private var offline = OfflineCacheStore.shared
    @State private var cachedCount = 0

    @State private var expandedIntro = false
    @State private var showAllChapters = false
    @State private var chapterFilter = ""

    struct Alternate: Identifiable {
        let id: UUID
        let item: SourceItem
        let source: BookSource
    }

    init(item: SourceItem, source: BookSource, shelf: BookshelfViewModel, store: SourceStore, onOpenBook: @escaping (Book) -> Void) {
        _item = State(initialValue: item)
        _source = State(initialValue: source)
        _shelf = ObservedObject(wrappedValue: shelf)
        _store = ObservedObject(wrappedValue: store)
        self.onOpenBook = onOpenBook
    }

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

                        if vm.meta.status.isEmpty == false || vm.meta.wordCount.isEmpty == false || vm.meta.latestChapter.isEmpty == false {
                            HStack(spacing: 6) {
                                if vm.meta.status.isEmpty == false {
                                    Text(vm.meta.status)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                                if vm.meta.wordCount.isEmpty == false {
                                    Text(vm.meta.wordCount)
                                }
                                if vm.meta.latestChapter.isEmpty == false {
                                    Text("最新：\(vm.meta.latestChapter)")
                                        .lineLimit(1)
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            if vm.meta.intro.isEmpty == false {
                Section {
                    Text(vm.meta.intro)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(expandedIntro ? nil : 6)
                    Button {
                        expandedIntro.toggle()
                    } label: {
                        Text(expandedIntro ? "收起简介" : "展开全部简介")
                            .font(.footnote)
                    }
                } header: {
                    Text("简介")
                }
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

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                    Text(cachedCount > 0 ? "已缓存 \(cachedCount) / \(vm.chapters.count) 章" : "还没缓存")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if offline.isRunning(link: item.link) {
                        ProgressView()
                    }
                }

                if offline.isRunning(link: item.link) {
                    ProgressView(value: offline.progress)
                    Text(offline.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("停止缓存") { offline.cancel() }
                        .foregroundStyle(.red)
                } else {
                    Button {
                        Task {
                            await offline.cache(source: source, item: item, chapters: vm.chapters, limit: 0)
                            refreshCached()
                            if let message = offline.finishedMessage { alertText = message }
                        }
                    } label: {
                        Text(cachedCount > 0 ? "接着缓存剩下的" : "整本缓存到本机")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(vm.chapters.isEmpty)

                    if cachedCount > 0 {
                        Button(role: .destructive) {
                            ChapterCache.clear(link: item.link)
                            refreshCached()
                        } label: {
                            Text("清空这本的缓存")
                        }
                    }
                }
            } header: {
                Text("离线缓存")
            } footer: {
                Text("缓存过的章节断网也能读；在线阅读时读一章也会自动存一章。")
            }

            Section {
                Button {
                    showSwitch = true
                    findAlternates()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(switching ? "正在别的源里找这本…" : "换源 · 当前：\(source.name)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if switching {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(switching)
            } footer: {
                Text("这本在别的源更全或广告更少时切过去，已读的章数照搬。")
            }

            if vm.chapters.isEmpty == false {
                Section {
                    ForEach(vm.chapters.prefix(50).indices, id: \.self) { index in
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
                                Text(TextScript.convert(Purifier.cleanTitle(vm.chapters[index].name), mode: scriptMode))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    Button {
                        chapterFilter = ""
                        showAllChapters = true
                    } label: {
                        Label(vm.chapters.count > 50 ? "查看全部 \(vm.chapters.count) 章" : "查看目录", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("目录 · 共 \(vm.chapters.count) 章")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshCached()
            if vm.chapters.isEmpty { await vm.loadChapters(source: source, item: item) }
            refreshCached()
        }
        .sheet(isPresented: $showSwitch) {
            switchSheet
        }
        .sheet(isPresented: $showAllChapters) {
            chapterSheet
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

    // MARK: - 换源

    private func refreshCached() {
        cachedCount = ChapterCache.cachedCount(link: item.link)
    }

    /// 简繁显示方式（跟设置页一致）
    private var scriptMode: TextScript {
        TextScript(rawValue: UserDefaults.standard.string(forKey: "reader.scriptMode") ?? "") ?? .auto
    }

    private var switchSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 15, weight: .medium))
                                .lineLimit(1)
                            Text("\(source.name) · 当前源")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text("下面是别的源里搜到的同名书，点一条就切过去。")
                }

                if alternates.isEmpty {
                    Section {
                        if switching {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("搜到 \(vm.searchedCount) / \(vm.plannedCount) 个源…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("别的源里没找到同名的这本。可以回上一页换个关键词再搜。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        ForEach(alternates) { alt in
                            Button {
                                apply(alt)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(alt.item.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(alt.source.name) · \(alt.item.author.isEmpty ? "未知作者" : alt.item.author)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } footer: {
                        Text("点一条就切过去，目录会重新取，读到第几章会照搬。")
                    }
                }
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showSwitch = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 全量目录

    private var filteredChapters: [(index: Int, chapter: SourceChapter)] {
        let keyword = chapterFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return vm.chapters.enumerated().map { (index: $0.offset, chapter: $0.element) }
        }
        return vm.chapters.enumerated().compactMap { offset, chapter in
            chapter.name.localizedCaseInsensitiveContains(keyword) ? (index: offset, chapter: chapter) : nil
        }
    }

    private var chapterSheet: some View {
        NavigationStack {
            List {
                let filtered = filteredChapters
                if filtered.isEmpty {
                    Text("没有匹配「\(chapterFilter)」的章节")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.index) { entry in
                        Button {
                            showAllChapters = false
                            startIndex = entry.index
                            reading = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(entry.index + 1)")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                                Text(TextScript.convert(Purifier.cleanTitle(entry.chapter.name), mode: scriptMode))
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .navigationTitle("目录 · \(vm.chapters.count) 章")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $chapterFilter, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showAllChapters = false }
                }
            }
        }
    }

    private func findAlternates() {
        guard switching == false else { return }
        switching = true
        alternates = []

        let title = item.name
        let target = Self.normalized(title)
        let pool = store.sources.filter {
            $0.enabled && $0.type == item.type && $0.id != source.id && $0.searchUnsupportedReason == nil
        }

        Task {
            let backup = vm.keyword
            vm.keyword = title
            await vm.search(sources: pool, limit: 12, store: nil)
            vm.keyword = backup

            var seen = Set<UUID>()
            var found: [Alternate] = []
            for result in vm.results {
                guard seen.contains(result.sourceID) == false else { continue }
                guard let alt = store.sources.first(where: { $0.id == result.sourceID }) else { continue }
                guard Self.similar(result.name, target) else { continue }
                seen.insert(result.sourceID)
                found.append(Alternate(id: result.sourceID, item: result, source: alt))
            }
            alternates = found
            switching = false
        }
    }

    private func apply(_ alt: Alternate) {
        let carry = savedIndex
        showSwitch = false
        item = alt.item
        source = alt.source
        vm.chapters = []
        vm.chapterError = nil
        refreshCached()

        Task {
            await vm.loadChapters(source: alt.source, item: alt.item)
            if carry > 0, vm.chapters.isEmpty == false {
                let target = min(carry, vm.chapters.count - 1)
                UserDefaults.standard.set(target, forKey: "readpos-\(alt.item.link)")
            }
        }
        alertText = "已切到「\(alt.source.name)」"
    }

    /// 只留中文、字母、数字，书名里的《》、空格、标点不算差异
    private static func normalized(_ raw: String) -> String {
        var out = ""
        for character in raw.lowercased() where character.isLetter || character.isNumber {
            out.append(character)
        }
        return out
    }

    private static func similar(_ lhs: String, _ target: String) -> Bool {
        let a = normalized(lhs)
        guard a.isEmpty == false, target.isEmpty == false else { return false }
        if a == target { return true }
        if a.contains(target) || target.contains(a) {
            return abs(a.count - target.count) <= 2
        }
        return false
    }
}
