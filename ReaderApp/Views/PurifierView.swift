//
//  PurifierView.swift
//  ReaderApp
//
//  替换净化：规则开关、自定义、测试
//

import SwiftUI

struct PurifierView: View {
    @ObservedObject private var store = PurifierStore.shared
    @AppStorage(Purifier.enabledKey) private var purifyOn = true

    @State private var editing: PurifyRule?
    @State private var adding = false
    @State private var sample = "本章未完，请点击下一页继续阅读\nwww.example.com 请收藏本站最新网址\n求推荐票，求月票，求打赏！\n这一段是正文，应该留着。"
    @State private var showSample = false

    var body: some View {
        Form {
            Section {
                Toggle("启用替换净化", isOn: $purifyOn)
            } footer: {
                Text("关闭后所有规则都不生效，正文按原样显示。规则只影响在线阅读的正文和章节标题，本机导入的书不动。")
            }

            Section {
                ForEach(store.rules) { rule in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(rule.name)
                                    .font(.system(size: 14, weight: .medium))
                                if rule.hitsTitle {
                                    Text("标题")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                }
                            }
                            Text(rule.pattern)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = rule }

                        Spacer(minLength: 6)

                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { store.setEnabled(rule.id, $0) }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.remove(rule.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }

                Button {
                    adding = true
                } label: {
                    Label("添加规则", systemImage: "plus.circle")
                }

                Button {
                    store.resetToPresets()
                } label: {
                    Label("恢复推荐规则", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("规则 · 启用 \(store.activeCount) 条")
            } footer: {
                Text("点一条规则可以改；右边开关单独控制。推荐规则覆盖了最常见的网址行、求票行和「下一页」尾巴。")
            }

            Section {
                Button {
                    showSample.toggle()
                } label: {
                    HStack {
                        Label("测试效果", systemImage: "text.magnifyingglass")
                        Spacer()
                        Image(systemName: showSample ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if showSample {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("原文")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $sample)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(height: 96)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("净化后")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(Purifier.preview(sample))
                                .font(.system(size: 13, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 96)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("测试")
            } footer: {
                Text("测试会跑一遍所有启用的规则（含标题规则），不影响实际阅读。")
            }
        }
        .navigationTitle("替换净化")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { updated in
                store.upsert(updated)
            }
        }
        .sheet(isPresented: $adding) {
            RuleEditor(rule: PurifyRule(name: "", pattern: "")) { created in
                store.upsert(created)
            }
        }
    }
}

// MARK: - 规则编辑

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PurifyRule
    private let onSave: (PurifyRule) -> Void

    init(rule: PurifyRule, onSave: @escaping (PurifyRule) -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
    }

    private var canSave: Bool {
        draft.name.trimmingCharacters(in: .whitespaces).isEmpty == false
            && draft.pattern.isEmpty == false
            && (draft.isRegex == false || Purifier.isValid(pattern: draft.pattern))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("规则名称", text: $draft.name)
                    TextField("替换成（留空就是删掉）", text: $draft.replacement)
                } header: {
                    Text("基本")
                }

                Section {
                    TextEditor(text: $draft.pattern)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 78)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                } header: {
                    Text("匹配内容")
                } footer: {
                    if draft.isRegex, draft.pattern.isEmpty == false, Purifier.isValid(pattern: draft.pattern) == false {
                        Text("这个正则写不通，检查一下括号和转义。")
                            .foregroundStyle(.red)
                    } else {
                        Text("用正则时，删带网址的整行可以写：(?m)^[^\\n]*?www\\.[^\\n]*$")
                    }
                }

                Section {
                    Toggle("用正则表达式", isOn: $draft.isRegex)
                    Toggle("只作用于章节标题", isOn: $draft.hitsTitle)
                    Toggle("启用这条规则", isOn: $draft.enabled)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "新规则" : "改规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(canSave == false)
                }
            }
        }
    }
}
