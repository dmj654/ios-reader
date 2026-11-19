//
//  SourceManagerView.swift
//  ReaderApp
//
//  书源管理：启用开关、编辑规则、粘贴/文件/网址导入、格式说明
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SourceManagerView: View {
    @ObservedObject var store: SourceStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var showPicker = false
    @State private var editing: BookSource?
    @State private var showDoc = false
    @State private var alertText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.sources.isEmpty {
                        Text("还没有书源")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.sources) { source in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Text("\(source.type.title) · \(source.baseUrl.isEmpty ? "未填地址" : source.baseUrl)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
                } header: {
                    Text("书源（点名称可编辑规则）")
                } footer: {
                    Text("只有打开开关、且填了地址和搜索规则的书源才会参与搜索。")
                }

                Section {
                    Button {
                        showPaste = true
                    } label: {
                        Label("粘贴 JSON 导入", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        showPicker = true
                    } label: {
                        Label("从文件导入 .json", systemImage: "folder")
                    }

                    Button {
                        showDoc = true
                    } label: {
                        Label("规则怎么写", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("添加")
                }
            }
            .navigationTitle("书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.json, .plainText, .item], allowsMultiple: false) { urls in
                    showPicker = false
                    guard let url = urls.first else { return }
                    if let error = store.importFile(at: url) {
                        alertText = error
                    } else {
                        alertText = "已导入"
                    }
                }
            }
            .sheet(isPresented: $showPaste) {
                pasteSheet
            }
            .sheet(isPresented: $showDoc) {
                SourceDocView()
            }
            .sheet(item: $editing) { source in
                SourceEditorView(source: source, store: store)
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
    }

    private var pasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("把书源 JSON 粘进来，单个对象或数组都行")
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
                    let error = store.importText(pasteText)
                    if let error {
                        alertText = error
                    } else {
                        pasteText = ""
                        showPaste = false
                    }
                } label: {
                    Text("导入")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

// MARK: - 书源编辑

struct SourceEditorView: View {
    let source: BookSource
    @ObservedObject var store: SourceStore

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var testKeyword = ""
    @State private var testResult = ""
    @State private var testing = false
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
                        .disabled(testing || testKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if testResult.isEmpty == false {
                        ScrollView {
                            Text(testResult)
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
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
        testing = true
        testResult = ""

        Task {
            do {
                let parsed = try SourceStore.decodeSource(text)
                let items = try await SourceClient.search(source: parsed, keyword: keyword)
                let sample = items.prefix(3).map { "\($0.name)\($0.author.isEmpty ? "" : "（\($0.author)）")" }
                testResult = "命中 \(items.count) 条\n" + sample.joined(separator: "\n")
            } catch let failure as SourceFailure {
                testResult = "失败：" + failure.message
            } catch {
                testResult = "失败：" + error.localizedDescription
            }
            testing = false
        }
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(BookSource.template)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("完整模板")
                        Spacer()
                        Button(copied ? "已复制" : "复制") {
                            UIPasteboard.general.string = BookSource.template
                            copied = true
                        }
                        .font(.caption)
                    }
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
                    Text("1. 用浏览器打开目标站点的搜索页，右键「查看源代码」，找到结果列表的容器和书名、链接所在的标签。")
                    Text("2. 把对应选择器填进 search.list / name / link，先点「测试」确认能搜出书名。")
                    Text("3. 再填 chapters（详情页的章节列表）和 content（章节页的正文容器），先只下「前 3 章」验证。")
                    Text("4. 漫画源：type 填 comic，content.images 填章节页里图片列表的选择器。")
                    Text("站点改版后规则会失效，回来改这几行就行，不用重装 App。")
                } header: {
                    Text("怎么调规则")
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
