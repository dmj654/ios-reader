//
//  SourceManagerView.swift
//  ReaderApp
//
//  书源管理：小说源 / 漫画源分开管，可新建、编辑规则、导入、逐级诊断
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SourceManagerView: View {
    @ObservedObject var store: SourceStore
    /// 从「设置」里推进来时不需要右上角「关闭」
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var editing: BookSource?
    @State private var showDoc = false
    @State private var alertText: String?
    @State private var importing = false
    @State private var pendingReport: SourceStore.ImportReport?
    @State private var report: SourceStore.ImportReport?
    @State private var showExport = false
    @State private var showCheck = false

    // 一千条源要用得上：搜索、筛选、排序、多选、批量操作
    @State private var query = ""
    @State private var kind: SourceKindFilter = .all
    @State private var sortMode: SourceSortMode = .recentSuccess
    @State private var groupFilter: String?
    @State private var selecting = false
    @State private var selectedIDs = Set<UUID>()
    /// 一次只铺这么多行，一千条也不至于一进页面就卡
    @State private var pageSize = 120
    @State private var groupsCache: [String] = []

    enum SourceKindFilter: String, CaseIterable, Identifiable {
        case all, novel, comic, enabled, disabled, ready, broken
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .novel: return "小说"
            case .comic: return "漫画"
            case .enabled: return "已启用"
            case .disabled: return "已停用"
            case .ready: return "规则完整"
            case .broken: return "缺东西"
            }
        }
    }

    enum SourceSortMode: String, CaseIterable, Identifiable {
        case recentSuccess, successCount, name, recentUsed, failFirst
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recentSuccess: return "最近能搜到的优先"
            case .successCount: return "搜成功次数多"
            case .name: return "按名称"
            case .recentUsed: return "最近用过的"
            case .failFirst: return "老是失败的优先"
            }
        }
        /// 胶囊按钮上用小字，别把一行撑爆
        var short: String {
            switch self {
            case .recentSuccess: return "最近成功"
            case .successCount: return "成功多"
            case .name: return "名称"
            case .recentUsed: return "最近用"
            case .failFirst: return "常失败"
            }
        }
    }

    /// 列表行用的轻量模型：筛选/排序/规则检查都只在 refresh() 里算一次，
    /// 渲染和开关不再重复做规则检查和日期格式化（一千条源时这是最大的卡顿来源）
    struct SourceRow: Identifiable {
        enum Status {
            case ready, disabled, jsUnsupported, broken
        }
        let id: UUID
        let name: String
        let detail: String?
        let status: Status
        let enabled: Bool
    }

    @State private var rows: [SourceRow] = []
    @State private var readyCount = 0
    @State private var loaded = false

    /// 首屏只铺 pageSize 条
    private var pagedRows: [SourceRow] {
        Array(rows.prefix(pageSize))
    }

    private func tint(of status: SourceRow.Status) -> Color {
        switch status {
        case .ready: return .green
        case .disabled: return .secondary
        case .jsUnsupported: return .red
        case .broken: return .orange
        }
    }

    /// 当前筛选 + 排序下的源，结果缓存成行模型
    private func refresh() {
        var list = store.sources

        switch kind {
        case .all: break
        case .novel: list = list.filter { $0.type == .novel }
        case .comic: list = list.filter { $0.type == .comic }
        case .enabled: list = list.filter { $0.enabled }
        case .disabled: list = list.filter { !$0.enabled }
        case .ready: list = list.filter { SourceStore.problems(for: $0).isEmpty }
        case .broken: list = list.filter { SourceStore.problems(for: $0).isEmpty == false }
        }

        if let groupFilter {
            list = list.filter { ($0.group ?? "") == groupFilter }
        }

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty == false {
            list = list.filter {
                $0.name.lowercased().contains(text)
                    || $0.baseUrl.lowercased().contains(text)
                    || ($0.group ?? "").lowercased().contains(text)
            }
        }

        switch sortMode {
        case .recentSuccess:
            list.sort { lhs, rhs in
                if lhs.successCount != rhs.successCount { return lhs.successCount > rhs.successCount }
                let l = lhs.lastSuccessAt ?? Date.distantPast
                let r = rhs.lastSuccessAt ?? Date.distantPast
                if l != r { return l > r }
                return lhs.name < rhs.name
            }
        case .successCount:
            list.sort { $0.successCount > $1.successCount }
        case .name:
            list.sort { $0.name < $1.name }
        case .recentUsed:
            list.sort { ($0.lastUsedAt ?? Date.distantPast) > ($1.lastUsedAt ?? Date.distantPast) }
        case .failFirst:
            list.sort { lhs, rhs in
                if lhs.failCount != rhs.failCount { return lhs.failCount > rhs.failCount }
                return lhs.name < rhs.name
            }
        }

        var ready = 0
        rows = list.map { source in
            let unsupported = source.searchUnsupportedReason
            let problems = SourceStore.problems(for: source)
            let status: SourceRow.Status
            if unsupported != nil {
                status = .jsUnsupported
            } else if problems.isEmpty == false {
                status = .broken
            } else if source.enabled == false {
                status = .disabled
            } else {
                status = .ready
                ready += 1
            }

            var parts: [String] = [source.type == .comic ? "漫画" : "小说"]
            if let group = source.group, group.isEmpty == false {
                parts.append(group)
            }
            if source.successCount > 0 {
                parts.append("成功 \(source.successCount)")
            }
            if let unsupported {
                parts.append("含 \(unsupported)")
            } else if problems.isEmpty == false {
                parts.append("缺 " + problems.joined(separator: "、"))
            }

            return SourceRow(
                id: source.id,
                name: source.name,
                detail: parts.joined(separator: " · "),
                status: status,
                enabled: source.enabled
            )
        }
        readyCount = ready
        loaded = true
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    controlBar
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                }

                Section {
                    if loaded == false {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在整理 \(store.sources.count) 条书源…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if rows.isEmpty {
                        Text(store.sources.isEmpty ? "还没有书源。右上角「＋」可以粘贴或从文件导入。" : "当前筛选下没有书源，换个条件或清空搜索词。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(pagedRows) { row in
                        rowView(row)
                    }

                    if rows.count > pagedRows.count {
                        Button {
                            pageSize += 150
                        } label: {
                            Label("再显示 150 条（还剩 \(rows.count - pagedRows.count) 条）", systemImage: "chevron.down")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                } header: {
                    Text("共 \(store.sources.count) 条 · 本机可用 \(readyCount) 条 · 当前 \(rows.count) 条")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
            }
            .navigationTitle("书源")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜名称 / 域名 / 分组"
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting {
                    batchBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = store.exportJSON()
                            alertText = "全部书源 JSON 已复制（\(store.sources.count) 条），可以保存到备忘录或发给自己。"
                        } label: {
                            Label("复制全部书源 JSON", systemImage: "doc.on.doc")
                        }
                        Button {
                            selecting.toggle()
                            if selecting == false { selectedIDs.removeAll() }
                        } label: {
                            Label(selecting ? "退出多选" : "多选 / 批量操作", systemImage: "checklist")
                        }
                        Button {
                            showCheck = true
                        } label: {
                            Label("书源体检", systemImage: "stethoscope")
                        }
                        Button {
                            showDoc = true
                        } label: {
                            Label("规则说明", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editing = store.addTemplate(.novel)
                        } label: {
                            Label("新建小说源", systemImage: "plus")
                        }
                        Button {
                            editing = store.addTemplate(.comic)
                        } label: {
                            Label("新建漫画源", systemImage: "plus")
                        }
                        Button {
                            showPaste = true
                        } label: {
                            Label("粘贴 JSON 导入", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            importBookSourcesFromFile()
                        } label: {
                            Label("从文件导入 .json", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if embedded == false {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showPaste, onDismiss: {
                if let pendingReport {
                    report = pendingReport
                    self.pendingReport = nil
                }
            }) {
                pasteSheet
            }
            .sheet(isPresented: $showDoc) {
                SourceDocView()
            }
            .sheet(item: $editing) { source in
                SourceEditorView(source: source, store: store)
            }
            .sheet(isPresented: Binding(
                get: { report != nil },
                set: { if $0 == false { report = nil } }
            )) {
                if let report {
                    reportSheet(report)
                }
            }
            .alert("书源", isPresented: Binding(
                get: { alertText != nil },
                set: { if $0 == false { alertText = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(alertText ?? "")
            }
            .onDisappear {
                store.flushPendingSave()
            }
            .onAppear {
                groupsCache = store.groups
                refresh()
            }
            .onChange(of: store.sources) { _, _ in
                groupsCache = store.groups
                refresh()
            }
            .onChange(of: kind) { _, _ in pageSize = 120; refresh() }
            .onChange(of: sortMode) { _, _ in pageSize = 120; refresh() }
            .onChange(of: groupFilter) { _, _ in pageSize = 120; refresh() }
            .onChange(of: query) { _, _ in pageSize = 120; refresh() }
            .sheet(isPresented: $showCheck) {
                SourceCheckView(store: store)
            }
        }
    }

    /// v1.8.1：选择器从顶层 VC 直接弹出，不再套 sheet
    private func importBookSourcesFromFile() {
        DocumentPickerHost.present(contentTypes: PickTypes.json, allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            Task {
                importing = true
                let result = await store.importFilePayload(at: url)
                importing = false
                // 等选择器完全收起来再弹结果，避免两个 presentation 打架
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    report = result
                }
            }
        }
    }

    private func reportSheet(_ report: SourceStore.ImportReport) -> some View {        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("书源已存进本地文件，下次打开还在。要换机就点左上角导出，复制 JSON 存起来。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("知道了") { report_clear() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func report_clear() {
        report = nil
    }

    // MARK: - 筛选 / 排序 / 批量

    private var controlBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SourceKindFilter.allCases) { item in
                    Button {
                        kind = item
                    } label: {
                        if kind == item {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                pill(icon: "line.3.horizontal.decrease", title: kind.title)
            }

            Menu {
                Button("全部分组") { groupFilter = nil }
                ForEach(groupsCache, id: \.self) { group in
                    Button(group) { groupFilter = group }
                }
            } label: {
                pill(icon: "folder", title: groupFilter ?? "分组")
            }

            Menu {
                ForEach(SourceSortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                pill(icon: "arrow.up.arrow.down", title: sortMode.short)
            }

            Spacer(minLength: 0)

            if selecting == false {
                Button {
                    selecting = true
                } label: {
                    Text("选择")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pill(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .foregroundStyle(AppTheme.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppTheme.card, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: 0.5))
    }

    private var batchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("已选 \(selectedIDs.count) / 共 \(rows.count)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                Spacer()
                Button(selectedIDs.count == rows.count ? "取消全选" : "全选当前") {
                    if selectedIDs.count == rows.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(rows.map(\.id))
                    }
                }
                .font(.footnote)
            }

            HStack(spacing: 8) {
                batchButton("启用", icon: "checkmark.circle", tint: .green) {
                    store.setEnabled(ids: selectedIDs, enabled: true)
                }
                batchButton("停用", icon: "pause.circle", tint: .orange) {
                    store.setEnabled(ids: selectedIDs, enabled: false)
                }
                batchButton("删除", icon: "trash", tint: .red) {
                    let count = selectedIDs.count
                    store.remove(ids: selectedIDs)
                    selectedIDs.removeAll()
                    alertText = "已删除 \(count) 条书源。"
                }
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBar()
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func batchButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func rowView(_ row: SourceRow) -> some View {
        let isSelected = selectedIDs.contains(row.id)

        return HStack(spacing: 9) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondary)
            }

            Circle()
                .fill(tint(of: row.status))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(row.status == .jsUnsupported || row.status == .broken ? AppTheme.secondary : AppTheme.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { tap(row) }

            if selecting == false {
                Toggle("", isOn: Binding(
                    get: { row.enabled },
                    set: { store.setEnabled(ids: [row.id], enabled: $0) }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 1)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(ids: [row.id])
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                edit(row.id)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func tap(_ row: SourceRow) {
        if selecting {
            if selectedIDs.contains(row.id) {
                selectedIDs.remove(row.id)
            } else {
                selectedIDs.insert(row.id)
            }
        } else {
            edit(row.id)
        }
    }

    private func edit(_ id: UUID) {
        guard let source = store.sources.first(where: { $0.id == id }) else { return }
        editing = source
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relativeDescription(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var pasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("支持「阅读 / Legado」导出的书源 JSON，会自动转换；也支持本 App 自己的精简格式。一次粘一条或整个数组都行。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                TextEditor(text: $pasteText)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke, lineWidth: 0.5))
                    .padding(.horizontal, 16)

                Button {
                    let text = pasteText
                    importing = true
                    Task {
                        let result = await store.importPayload(text)
                        importing = false
                        pendingReport = result
                        pasteText = ""
                        showPaste = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if importing { ProgressView().scaleEffect(0.8) }
                        Text(importing ? "正在解析…" : "导入")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(importing || pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
            .navigationTitle("粘贴导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showPaste = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("填模板") {
                        pasteText = BookSource.template
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 书源编辑 + 逐级诊断

struct SourceEditorView: View {
    let source: BookSource
    @ObservedObject var store: SourceStore

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var testKeyword = ""
    @State private var stage: SourceClient.DebugStage = .search
    @State private var output: SourceClient.DebugOutput?
    @State private var testing = false
    @State private var showHTML = false
    @State private var alertText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Picker("诊断到哪一步", selection: $stage) {
                        ForEach(SourceClient.DebugStage.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        TextField("测试关键词", text: $testKeyword)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()

                        Button {
                            runTest()
                        } label: {
                            if testing {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("测试")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(testing)
                    }

                    if let output {
                        ScrollView {
                            Text(output.detail)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)

                        if output.html.isEmpty == false {
                            Button {
                                showHTML = true
                            } label: {
                                Label("查看抓到的原始页面（\(output.html.count) 字）", systemImage: "doc.text.magnifyingglass")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let error = store.update(source, json: text) {
                            alertText = error
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showHTML) {
                if let output {
                    SourceHTMLView(url: output.pageURL, html: output.html)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { alertText != nil },
                set: { if $0 == false { alertText = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(alertText ?? "")
            }
            .onAppear {
                if text.isEmpty { text = source.prettyJSON() }
            }
        }
    }

    private func runTest() {
        let keyword = testKeyword.trimmingCharacters(in: .whitespaces)
        guard keyword.isEmpty == false else {
            alertText = "先输入一个测试关键词"
            return
        }

        let parsed: BookSource
        do {
            parsed = try SourceStore.decodeSource(text)
        } catch {
            alertText = (error as? LocalizedError)?.errorDescription ?? "JSON 解析失败"
            return
        }

        testing = true
        output = nil

        Task {
            output = await SourceClient.debug(source: parsed, keyword: keyword, stage: stage)
            testing = false
        }
    }
}

// MARK: - 原始页面查看

struct SourceHTMLView: View {
    let url: String
    let html: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var shown: String {
        String(html.prefix(6000))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                ScrollView([.horizontal, .vertical]) {
                    Text(shown)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                }
            }
            .navigationTitle("原始页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "已复制" : "复制全文") {
                        UIPasteboard.general.string = html
                        copied = true
                    }
                    .font(.caption)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 规则说明

struct SourceDocView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private let rows: [(String, String)] = [
        ("css:选择器", "取元素，例：css:#chapterlist li、css:div.book-list > li"),
        ("json:路径", "取 JSON 字段，例：json:data.books[0].name"),
        ("regex:正则", "在文本里抓匹配，第一个括号是结果"),
        ("@text", "取元素里的纯文本（保留段落换行）"),
        ("@html", "取元素原始 HTML"),
        ("@href", "取元素 href，自动补成绝对地址"),
        ("@src", "取元素 src，自动补成绝对地址"),
        ("@attr(名字)", "取任意属性，懒加载图常写 @attr(data-src)"),
        ("{{key}}", "搜索关键词（已 URL 编码）"),
        ("{{keyRaw}}", "搜索关键词原文，POST 表单常用"),
        ("{{page}}", "页码，从 1 开始"),
        ("{{link}}", "当前条目 / 章节的地址"),
        ("{{base}}", "书源的 baseUrl")
    ]

    private let legadoRows: [(String, String)] = [
        ("@css:选择器", "阅读(Legado)的 CSS 写法，等价于 css:"),
        ("class.名字", "等价于 CSS 的 .名字"),
        ("tag.名字", "等价于 CSS 的 标签名"),
        ("//xpath", "简化的 XPath，会自动转成 CSS；带 following-sibling、ancestor 这类会报不支持"),
        ("$....", "JSON 路径，等价于 json:"),
        ("@text / @html / @href / @src", "取值后缀，和上面通用"),
        ("@tag.li / @css:xxx", "在已取到的元素里再往下选一层"),
        ("##正则##替换", "取到结果后做正则替换，常用来删广告"),
        ("aaa||bbb", "前一条取不到就试后一条"),
        ("<js> / @js:", "跑不了：本 App 没有 JS 引擎，会明确提示")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(BookSource.template)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("小说源模板")
                        Spacer()
                        Button(copied ? "已复制" : "复制") {
                            UIPasteboard.general.string = BookSource.template
                            copied = true
                        }
                        .font(.caption)
                    }
                } footer: {
                    Text("漫画源把 type 改成 \"comic\"，content 里把 text 换成 images，例：\"images\": \"css:#images img@src\"")
                }

                Section {
                    ForEach(rows.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rows[index].0)
                                .font(.system(size: 12, design: .monospaced))
                            Text(rows[index].1)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("规则语法")
                }

                Section {
                    ForEach(legadoRows.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(legadoRows[index].0)
                                .font(.system(size: 12, design: .monospaced))
                            Text(legadoRows[index].1)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("也认「阅读 / Legado」的写法")
                } footer: {
                    Text("导入 Legado 书源时会自动转成这里的结构，规则原样保留，靠上面这套语法跑。")
                }

                Section {
                    Text("1. 在编辑器里按「搜索 → 目录 → 正文」三步依次测，哪一步没数据就修那一步的规则。")
                    Text("2. 每步都能「查看抓到的原始页面」，拿页面里的真实标签名去改选择器，不用猜。")
                    Text("3. 站点改版后选择器会失效，回来改这几行就行，不用重装 App。")
                } header: {
                    Text("排查顺序")
                } footer: {
                    Text("仅用于你自己有权访问的站点，请遵守对方站点的使用条款。")
                }
            }
            .navigationTitle("书源规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
