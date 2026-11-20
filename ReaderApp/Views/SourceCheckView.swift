//
//  SourceCheckView.swift
//  ReaderApp
//
//  书源体检：批量拿一个关键词去试，直接分出「能搜到 / 能连上但没结果 / 连不上」
//

import SwiftUI

struct SourceCheckView: View {
    @ObservedObject var store: SourceStore
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = "斗罗大陆"
    @State private var limit = 60
    @State private var running = false
    @State private var cancelRequested = false

    @State private var done = 0
    @State private var total = 0

    /// 能搜到书的源，value 是搜到的条数
    @State private var okCounts: [UUID: Int] = [:]
    /// 页面能拿到，但一条都没提取出来（规则对不上 / 要登录）
    @State private var reachedIDs: [UUID] = []
    /// 连不上，按原因归并
    @State private var failBuckets: [String: Int] = [:]
    @State private var outcomes: [UUID: Bool] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("测试关键词（用一本大众书名最好）", text: $keyword)
                        .autocorrectionDisabled()

                    Picker("一次测几个源", selection: $limit) {
                        Text("30 个").tag(30)
                        Text("60 个").tag(60)
                        Text("150 个").tag(150)
                        Text("全部").tag(9999)
                    }

                    if running {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("已测 \(done) / \(total)")
                                .font(.footnote)
                                .monospacedDigit()
                            Spacer()
                            Button("停止") {
                                cancelRequested = true
                            }
                            .font(.footnote)
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            start()
                        } label: {
                            Label(done == 0 ? "开始体检" : "重新体检", systemImage: "stethoscope")
                        }
                        .disabled(store.enabledSources.isEmpty)
                    }
                } header: {
                    Text("怎么测")
                } footer: {
                    Text("只测「已启用」的源，按以前搜成功过的优先。每批并发 6 个、单个最多等 10 秒，所以 60 个源大概一分钟。")
                }

                if okCounts.isEmpty == false {
                    Section {
                        ForEach(okSources) { source in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(source.name)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(okCounts[source.id] ?? 0) 条")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Button {
                            useOnlyOK()
                        } label: {
                            Label("只启用这些能搜到的（其它全部停用）", systemImage: "checkmark.seal")
                                .font(.system(size: 13, weight: .medium))
                        }
                    } header: {
                        Text("能搜到书 · \(okCounts.count) 个")
                    }
                }

                if reachedIDs.isEmpty == false {
                    Section {
                        Text("有 \(reachedIDs.count) 个源能连上站点，但一条书都提取不出来。多半是规则和现在的页面对不上，或者站点要登录/验证码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(reachedSources.prefix(12)) { source in
                            Text(source.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("能连上但没结果")
                    }
                }

                if failBuckets.isEmpty == false {
                    Section {
                        ForEach(failBuckets.keys.sorted { (failBuckets[$0] ?? 0) > (failBuckets[$1] ?? 0) }, id: \.self) { key in
                            HStack(spacing: 8) {
                                Text("×\(failBuckets[key] ?? 0)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule())
                                Text(key)
                                    .font(.system(size: 12))
                            }
                        }
                    } header: {
                        Text("连不上")
                    }
                    Section {
                        Button(role: .destructive) {
                            store.setEnabled(ids: Set(failedIDs), enabled: false)
                            failBuckets = [:]
                        } label: {
                            Label("把这 \(failedIDs.count) 个连不上的停用", systemImage: "pause.circle")
                                .font(.system(size: 13))
                        }
                    }
                }

                if done > 0 && running == false && okCounts.isEmpty {
                    Section {
                        Text("这批源一个都没搜到。先看下面的「连不上」里是哪一类：全是「网络超时」说明这些站点在这台手机上打不开；有「403」说明站点拦非浏览器请求；如果是「规则对不上页面」，那是书源规则需要改。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("书源体检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        cancelRequested = true
                        store.flushPendingSave()
                        dismiss()
                    }
                }
            }
        }
    }

    private var okSources: [BookSource] {
        store.sources.filter { okCounts[$0.id] != nil }
    }

    private var reachedSources: [BookSource] {
        store.sources.filter { reachedIDs.contains($0.id) }
    }

    private var failedIDs: [UUID] {
        Array(outcomes.filter { $0.value == false }.keys)
    }

    private func useOnlyOK() {
        let all = Set(store.sources.map(\.id))
        store.setEnabled(ids: all, enabled: false)
        store.setEnabled(ids: Set(okCounts.keys), enabled: true)
        store.flushPendingSave()
    }

    private func start() {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        let candidates = Array(
            store.enabledSources
                .sorted { lhs, rhs in
                    if lhs.successCount != rhs.successCount { return lhs.successCount > rhs.successCount }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .prefix(max(1, limit))
        )
        guard candidates.isEmpty == false else { return }

        cancelRequested = false
        running = true
        done = 0
        total = candidates.count
        okCounts = [:]
        reachedIDs = []
        failBuckets = [:]
        outcomes = [:]

        Task {
            let batchSize = 6
            var start = 0

            while start < candidates.count {
                if cancelRequested { break }
                let end = min(start + batchSize, candidates.count)
                let slice = Array(candidates[start..<end])

                let batch = await withTaskGroup(of: (BookSource, Result<[SourceItem], SourceFailure>).self) {
                    group -> [(BookSource, Result<[SourceItem], SourceFailure>)] in
                    for source in slice {
                        group.addTask {
                            do {
                                return (source, .success(try await SourceClient.search(source: source, keyword: text, timeout: 10)))
                            } catch let failure as SourceFailure {
                                return (source, .failure(failure))
                            } catch {
                                return (source, .failure(SourceFailure(message: error.localizedDescription)))
                            }
                        }
                    }
                    var collected: [(BookSource, Result<[SourceItem], SourceFailure>)] = []
                    for await item in group { collected.append(item) }
                    return collected
                }

                if cancelRequested { break }

                for (source, result) in batch {
                    switch result {
                    case .success(let items):
                        if items.isEmpty {
                            reachedIDs.append(source.id)
                            outcomes[source.id] = false
                        } else {
                            okCounts[source.id] = items.count
                            outcomes[source.id] = true
                        }
                    case .failure(let failure):
                        let key = SourceViewModel.failureKey(failure.message)
                        failBuckets[key, default: 0] += 1
                        outcomes[source.id] = false
                    }
                }

                done = min(end, candidates.count)
                start = end
            }

            store.applySearchOutcomes(outcomes)
            store.flushPendingSave()
            running = false
        }
    }
}
