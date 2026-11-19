//
//  ComicSettingsView.swift
//  ReaderApp
//
//  漫画阅读的个性化设置面板（阅读页里的齿轮和设置页里都能进）
//

import SwiftUI

struct ComicSettingsView: View {
    @ObservedObject var settings: ReadingSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("阅读方式", selection: $settings.comicMode) {
                        ForEach(ComicReadMode.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("图片适配", selection: $settings.comicFit) {
                        ForEach(ComicFitMode.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }

                    Picker("阅读方向", selection: $settings.comicDirection) {
                        ForEach(ComicDirection.allCases) { direction in
                            Text(direction.name).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("阅读方式")
                } footer: {
                    Text("\(settings.comicFit.hint)　\(settings.comicDirection.hint)")
                }

                Section {
                    Picker("背景", selection: $settings.comicBackground) {
                        ForEach(ComicBackground.allCases) { bg in
                            Text(bg.name).tag(bg)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("自动裁掉白边", isOn: $settings.comicAutoTrim)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("压暗画面")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.comicDim * 100))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.comicDim, in: 0...0.6, step: 0.05)
                    }
                } header: {
                    Text("画面")
                } footer: {
                    Text("自动裁白边会去掉扫描页四周的空白；压暗适合夜里看，20%~40% 比较舒服。")
                }

                Section {
                    Picker("点按区域", selection: $settings.comicTapZone) {
                        ForEach(ComicTapZone.allCases) { zone in
                            Text(zone.name).tag(zone)
                        }
                    }
                    Picker("工具栏", selection: $settings.comicChrome) {
                        ForEach(ComicChromeMode.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                    if settings.comicChrome == .autoHide {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("自动隐藏延时")
                                Spacer()
                                Text(String(format: "%.1f 秒", settings.comicAutoHideDelay))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.comicAutoHideDelay, in: 1...8, step: 0.5)
                        }
                    }

                    Toggle("显示进度线", isOn: $settings.comicShowProgress)
                    Toggle("显示页码", isOn: $settings.comicShowPageNumber)
                    Toggle("双击放大", isOn: $settings.comicDoubleTapZoom)
                } header: {
                    Text("操作")
                } footer: {
                    Text(settings.comicTapZone.hint)
                }

                Section {
                    Stepper("预读 \(settings.comicPreload) 页", value: $settings.comicPreload, in: 0...4)
                    Toggle("阅读时屏幕常亮", isOn: $settings.comicKeepAwake)
                } header: {
                    Text("性能")
                } footer: {
                    Text("预读越多翻页越顺，内存占用也越高；手机内存紧张时调成 1 页。")
                }

                Section {
                    Button("恢复漫画默认设置") {
                        settings.resetComicDefaults()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("漫画阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
