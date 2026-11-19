//
//  SettingsView.swift
//  ReaderApp
//
//  阅读设置面板
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ReadingSettings
    @Environment(\.dismiss) private var dismiss

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
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
