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
                    if store.novelSources.isEmpty {
                        Text("还没有小说源")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.novelSources) { source in
                        row(source)
                    }
                    Button {
                        editing = store.addTemplate(.novel)
                    } label: {
                        Label("新建小说源", systemImage: "plus")
                    }
                } header: {
                    Text("小说源 · \(store.novelSources.count)")
                } footer: {
                    Text("只参与小说搜索，关注册后下载成 TXT。")
                }

                Section {
                    if store.comicSources.isEmpty {
                        Text("还没有漫画源")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.comicSources) { source in
                        row(source)
                    }
                    Button {
                        editing = store.addTemplate(.comic)
                    } label: {
                        Label("新建漫画源", systemImage: "plus")
                    }
                } header: {
                    Text("漫画源 · \(store.comicSources.count)")
                } footer: {
                    Text("只参与漫画搜索，下下来打包成 CBZ。")
                }

                Section {
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
                    Button {
                        showDoc = true
                    } label: {
                        Label("规则怎么写", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("导入")
                } footer: {
                    Text("导入时会先检查规则是否完整，缺字段的书源会被挡下来并告诉你缺什么。")
                }
            }
            .navigationTitle("书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = store.exportJSON()
                            alertText = "全部书源 JSON 已复制（\(store.sources.count) 条），可以保存到备忘录或发给自己。"
                        } label: {
                            Label("复制全部书源 JSON", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
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

    private func row(_ source: BookSource) -> some View {
        let problems = SourceStore.problems(for: source)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(source.baseUrl.isEmpty ? "未填地址" : source.baseUrl)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if problems.isEmpty == false {
                    Text("缺 \(problems.joined(separator: "、"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = source }

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { store.setEnabled(source, enabled: $0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(source)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editing = source
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
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
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
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
