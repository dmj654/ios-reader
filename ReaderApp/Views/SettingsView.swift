//
//  SettingsView.swift
//  ReaderApp
//
//  阅读设置面板
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ReadingSettings
    var sources: SourceStore? = nil
    var books: [Book] = []
    /// 作为底部「设置」tab 常驻时没有 sheet 可关闭
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("stats.dailyGoalMinutes") private var goalMinutes: Int = 30
    @State private var showManager = false
    @State private var showStats = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(settings.fontSize))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.fontSize, in: 13...30, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("行距")
                            Spacer()
                            Text(String(format: "%.0f", settings.lineSpacing))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.lineSpacing, in: 2...18, step: 1)
                    }
                } header: {
                    Text("排版")
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button {
                                settings.theme = theme
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(theme.swatch)
                                        .frame(width: 38, height: 38)
                                        .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 0.5))
                                    if settings.theme == theme {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(theme.foreground)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)

                    Text("当前：\(settings.theme.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("背景")
                }

                Section {
                    Picker("翻页方式", selection: $settings.pageTurn) {
                        ForEach(PageTurnStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("翻页")
                }

                Section {
                    NavigationLink {
                        ComicSettingsView(settings: settings)
                    } label: {
                        HStack {
                            Text("漫画阅读设置")
                            Spacer()
                            Text(settings.comicMode.name + " · " + settings.comicFit.name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("漫画")
                } footer: {
                    Text("阅读方式、适配、方向、工具栏、点按区域、裁白边、压暗、预读等都可以单独调整。")
                }

                Section {
                    Picker("每日阅读目标", selection: $goalMinutes) {
                        ForEach([10, 15, 20, 30, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("阅读统计")
                } footer: {
                    Text("书架顶部显示今天读了多久、连续几天，点进去看热力图和排行。全部只存本机。")
                }

                if let sources {
                    Section {
                        Button {
                            showManager = true
                        } label: {
                            HStack {
                                Text("书源管理")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(sources.sources.filter { $0.enabled }.count)/\(sources.sources.count)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Button {
                            showStats = true
                        } label: {
                            HStack {
                                Text("阅读记录与排行")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text("书源与数据")
                    } footer: {
                        Text("导入 Legado 书源 JSON、开关单个源、批量停用用不了的源都在这里。")
                    }
                }

                Section {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text(verbatim: Self.versionText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("本地阅读器 · 数据全部保存在本机，不联网同步。")
                }
            }
            .navigationTitle(embedded ? "设置" : "阅读设置")
            .navigationBarTitleDisplayMode(embedded ? .large : .inline)
            .toolbar {
                if embedded == false {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showManager) {
                if let sources {
                    SourceManagerView(store: sources)
                }
            }
            .sheet(isPresented: $showStats) {
                StatsView(store: ReadingStatsStore.shared, books: books)
            }
        }
    }

    private static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) (\(build))"
    }
}
