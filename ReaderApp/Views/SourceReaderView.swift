//
//  SourceReaderView.swift
//  ReaderApp
//
//  在线阅读：按章抓取、预载后两章、记住读到第几章
//  界面与书架小说阅读页对齐：统一悬浮胶囊工具条、全局主题/字号/行距/段距/字体/简繁
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
    @State private var showSettings = false
    @State private var loadedIndex = -1

    @ObservedObject private var speech = SpeechReader.shared
    @StateObject private var settings = ReadingSettings()

    init(source: BookSource, item: SourceItem, chapters: [SourceChapter], startIndex: Int) {
        self.source = source
        self.item = item
        self.chapters = chapters
        _index = State(initialValue: max(0, min(startIndex, max(0, chapters.count - 1))))
    }

    private var ink: Color { settings.theme.foreground }

    var body: some View {
        ZStack {
            settings.theme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: settings.paragraphSpacing) {
                    Text(TextScript.convert(Purifier.cleanTitle(chapters.indices.contains(index) ? chapters[index].name : "…"), mode: settings.scriptMode))
                        .font(FontLibrary.font(name: settings.fontName, size: settings.fontSize + 4))
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                        .padding(.bottom, 2)

                    if loading && text.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在抓正文…")
                                .font(.footnote)
                                .foregroundStyle(ink.opacity(0.6))
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
                        Text(TextScript.convert(text, mode: settings.scriptMode))
                            .font(FontLibrary.font(name: settings.fontName, size: settings.fontSize))
                            .fontWeight(settings.boldBody ? .semibold : .regular)
                            .lineSpacing(settings.lineSpacing)
                            .foregroundStyle(ink)
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
                                        .foregroundStyle(ink.opacity(0.55))
                                }
                            }
                            Text("\(index + 1) / \(chapters.count)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(ink.opacity(0.4))
                            if index + 1 < chapters.count {
                                Button {
                                    load(index + 1)
                                } label: {
                                    Text("下一章 ›")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ink.opacity(0.55))
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

            if chrome {
                VStack(spacing: 0) {
                    topCapsule
                    Spacer(minLength: 0)
                    bottomCapsule
                }
                .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDirectory) {
            directorySheet
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
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

    // MARK: - 统一悬浮胶囊工具条

    private var topCapsule: some View {
        ReaderCapsule(dark: settings.theme.isDark) {
            HStack(spacing: 2) {
                ChromeIconButton(systemName: "chevron.left", tint: ink) {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(source.name)
                        .font(.system(size: 10))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(index + 1)/\(chapters.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.55))
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
        .padding(.top, ReaderChromeMetrics.topGap)
    }

    private var bottomCapsule: some View {
        ReaderCapsule(dark: settings.theme.isDark) {
            HStack(spacing: 0) {
                ChromeIconButton(systemName: "list.bullet", tint: ink) {
                    showDirectory = true
                }

                ChromeProgressTrack(fraction: chapterBinding, tint: ink) {
                    saveProgress()
                }
                .padding(.horizontal, 2)

                Menu {
                    Button {
                        toggleSpeech()
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
                        .font(.system(size: ReaderChromeMetrics.iconSize, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(width: ReaderChromeMetrics.height, height: ReaderChromeMetrics.height)
                        .contentShape(Rectangle())
                }

                ChromeIconButton(systemName: "textformat", tint: ink) {
                    showSettings = true
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, ReaderChromeMetrics.horizontalInset)
        .padding(.bottom, ReaderChromeMetrics.bottomGap)
    }

    private var chapterFraction: Double {
        guard chapters.count > 1 else { return 0 }
        return Double(min(max(index, 0), chapters.count - 1)) / Double(chapters.count - 1)
    }

    private var chapterBinding: Binding<Double> {
        Binding(
            get: { chapterFraction },
            set: { jump(toFraction: $0) }
        )
    }

    private func jump(toFraction fraction: Double) {
        guard chapters.count > 1 else { return }
        let span = Double(chapters.count - 1)
        let target = Int((fraction * span).rounded())
        load(min(chapters.count - 1, max(0, target)))
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
                            Text(TextScript.convert(Purifier.cleanTitle(chapters[i].name), mode: settings.scriptMode))
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

    // MARK: - 朗读

    private func toggleSpeech() {
        if speech.speaking {
            speech.stop()
        } else {
            speech.speak(text, key: chapters.indices.contains(index) ? chapters[index].link : item.link)
        }
    }

    /// 改语速后从本章开头重读，不然要等下一段才生效
    private func setSpeechRate(_ value: Float) {
        speech.rate = min(0.65, max(0.35, value))
        if speech.speaking {
            speech.speak(text, key: chapters.indices.contains(index) ? chapters[index].link : item.link)
        }
    }

    // MARK: - 抓取

    private func load(_ target: Int, force: Bool = false) {
        guard chapters.indices.contains(target) else { return }
        let chapter = chapters[target]

        if force == false, let cached = cache[target] {
            index = target
            text = Purifier.clean(cached)
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

        // 有离线缓存就直接用，断网也能看
        if force == false, let disk = ChapterCache.text(link: item.link, index: target) {
            cache[target] = disk
            text = Purifier.clean(disk)
            loading = false
            loadedIndex = target
            saveProgress()
            prefetchAround(target)
            return
        }

        Task {
            do {
                let body = try await SourceClient.chapterText(source: source, chapter: chapter)
                cache[target] = body
                ChapterCache.store(link: item.link, index: target, text: body)
                if index == target {
                    text = Purifier.clean(body)
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
                    ChapterCache.store(link: item.link, index: target, text: body)
                }
                prefetching.remove(target)
            }
        }
    }

    private func saveProgress() {
        UserDefaults.standard.set(index, forKey: "readpos-\(item.link)")
    }
}
