//
//  SourceReaderView.swift
//  ReaderApp
//
//  在线阅读：按章抓取、预载后两章、记住读到第几章
//

import SwiftUI

struct SourceReaderView: View {
    let source: BookSource
    let item: SourceItem
    let chapters: [SourceChapter]

    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var text = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var cache: [Int: String] = [:]
    @State private var prefetching = Set<Int>()
    @State private var chrome = true
    @State private var showDirectory = false
    @State private var fontSize: Double = 18
    @State private var loadedIndex = -1

    @ObservedObject private var speech = SpeechReader.shared

    init(source: BookSource, item: SourceItem, chapters: [SourceChapter], startIndex: Int) {
        self.source = source
        self.item = item
        self.chapters = chapters
        _index = State(initialValue: max(0, min(startIndex, max(0, chapters.count - 1))))
        _fontSize = State(initialValue: UserDefaults.standard.double(forKey: "sourceReaderFontSize") > 0
                          ? UserDefaults.standard.double(forKey: "sourceReaderFontSize")
                          : 18)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(chapters.indices.contains(index) ? chapters[index].name : "…")
                        .font(.system(size: fontSize + 4, weight: .semibold))
                        .padding(.bottom, 2)

                    if loading && text.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在抓正文…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                    } else if let errorText {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                            Button("重试") { load(index, force: true) }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 30)
                    } else {
                        Text(text)
                            .font(.system(size: fontSize))
                            .lineSpacing(fontSize * 0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            if index > 0 {
                                Button {
                                    load(index - 1)
                                } label: {
                                    Text("‹ 上一章")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(index + 1) / \(chapters.count)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            if index + 1 < chapters.count {
                                Button {
                                    load(index + 1)
                                } label: {
                                    Text("下一章 ›")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { chrome.toggle() }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if chrome { topBar }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if chrome { bottomBar }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDirectory) {
            directorySheet
        }
        .onAppear {
            if loadedIndex != index { load(index) }
        }
        .onChange(of: index) { _, _ in
            if speech.speaking { speech.stop() }
        }
        .onDisappear {
            speech.stop()
        }
    }

    // MARK: - 顶栏 / 底栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(source.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if prefetching.isEmpty == false {
                Text("预载 \(prefetching.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Button {
                load(index - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(index <= 0)

            Button {
                showDirectory = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                    Text("\(index + 1)/\(chapters.count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
            }

            Button {
                load(index + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(index + 1 >= chapters.count)

            Menu {
                Button {
                    if speech.speaking {
                        speech.stop()
                    } else {
                        speech.speak(text, key: chapters.indices.contains(index) ? chapters[index].link : item.link)
                    }
                } label: {
                    Label(speech.speaking ? "停止朗读" : "朗读本章", systemImage: speech.speaking ? "stop.fill" : "speaker.wave.2")
                }

                if speech.speaking {
                    Button {
                        if speech.paused { speech.resume() } else { speech.pause() }
                    } label: {
                        Label(speech.paused ? "继续朗读" : "暂停一下", systemImage: speech.paused ? "play.fill" : "pause.fill")
                    }
                }

                Button("慢一点") { setSpeechRate(speech.rate - 0.05) }
                Button("快一点") { setSpeechRate(speech.rate + 0.05) }
            } label: {
                Image(systemName: speech.speaking ? "speaker.wave.2.fill" : "speaker.wave.2")
            }

            Menu {
                Button("小一点") { setFont(fontSize - 1) }
                Button("大一点") { setFont(fontSize + 1) }
                Button("恢复默认") { setFont(18) }
            } label: {
                Image(systemName: "textformat.size")
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var directorySheet: some View {
        NavigationStack {
            List {
                ForEach(chapters.indices, id: \.self) { i in
                    Button {
                        showDirectory = false
                        load(i)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 34, alignment: .trailing)
                            Text(chapters[i].name)
                                .font(.system(size: 14))
                                .foregroundStyle(i == index ? Color.accentColor : Color.primary)
                            if i == index {
                                Spacer()
                                Image(systemName: "book.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("目录 · \(chapters.count) 章")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showDirectory = false }
                }
            }
        }
    }

    // MARK: - 抓取

    private func setFont(_ value: Double) {
        fontSize = min(26, max(13, value))
        UserDefaults.standard.set(fontSize, forKey: "sourceReaderFontSize")
    }

    /// 改语速后从本章开头重读，不然要等下一段才生效
    private func setSpeechRate(_ value: Float) {
        speech.rate = min(0.65, max(0.35, value))
        if speech.speaking {
            speech.speak(text, key: chapters.indices.contains(index) ? chapters[index].link : item.link)
        }
    }

    private func load(_ target: Int, force: Bool = false) {
        guard chapters.indices.contains(target) else { return }
        let chapter = chapters[target]

        if force == false, let cached = cache[target] {
            index = target
            text = cached
            loadedIndex = target
            errorText = nil
            loading = false
            saveProgress()
            prefetchAround(target)
            return
        }

        index = target
        loading = true
        text = cache[target] ?? ""
        errorText = nil

        Task {
            do {
                let body = try await SourceClient.chapterText(source: source, chapter: chapter)
                cache[target] = body
                if index == target {
                    text = body
                    loading = false
                    loadedIndex = target
                }
                saveProgress()
                prefetchAround(target)
            } catch let failure as SourceFailure {
                if index == target {
                    errorText = failure.message
                    loading = false
                }
            } catch {
                if index == target {
                    errorText = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    /// 预载后两章 + 前一章，翻页时基本是瞬间出
    private func prefetchAround(_ center: Int) {
        for offset in [1, 2, -1] {
            let target = center + offset
            guard chapters.indices.contains(target) else { continue }
            guard cache[target] == nil, prefetching.contains(target) == false else { continue }

            prefetching.insert(target)
            let chapter = chapters[target]
            Task {
                if let body = try? await SourceClient.chapterText(source: source, chapter: chapter) {
                    cache[target] = body
                }
                prefetching.remove(target)
            }
        }
    }

    private func saveProgress() {
        UserDefaults.standard.set(index, forKey: "readpos-\(item.link)")
    }
}
