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
    var shelf: BookshelfViewModel? = nil
    /// 作为底部「设置」tab 常驻时没有 sheet 可关闭
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("stats.dailyGoalMinutes") private var goalMinutes: Int = 30
    @State private var showManager = false
    @State private var showStats = false
    @ObservedObject private var fonts = FontStore.shared
    @ObservedObject private var purifier = PurifierStore.shared
    @ObservedObject private var backup = BackupStore.shared
    @ObservedObject private var dav = WebDAVStore.shared
    @State private var fontMessage: String?
    @State private var backupMessage: String?
    @State private var showWebDAV = false
    @State private var davServer = ""
    @State private var davUser = ""
    @State private var davPass = ""
    @State private var davMessage: String?

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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("段距")
                            Spacer()
                            Text(String(format: "%.0f", settings.paragraphSpacing))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.paragraphSpacing, in: 0...16, step: 1)
                    }
                    Toggle("正文加粗", isOn: $settings.boldBody)
                    Picker("简繁显示", selection: $settings.scriptMode) {
                        ForEach(TextScript.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("排版")
                }

                Section {
                    Picker("正文字体", selection: Binding(
                        get: { settings.fontName ?? "" },
                        set: { settings.fontName = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("系统默认").tag("")
                        ForEach(fonts.items) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        importFont()
                    } label: {
                        Label("导入字体（ttf / otf）", systemImage: "textformat")
                    }

                    ForEach(fonts.items) { item in
                        HStack {
                            Text(item.displayName)
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if settings.fontName == item.id {
                                Text("使用中")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                            }
                            Text(item.fileName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if settings.fontName == item.id { settings.fontName = nil }
                                fonts.remove(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("字体")
                } footer: {
                    Text("把 ttf / otf 放进「文件」App 后点导入；删掉字体，正文自动回到系统字体。排版会按新字体重新分页。")
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

                Section {
                    NavigationLink {
                        PurifierView()
                    } label: {
                        HStack {
                            Text("替换净化")
                            Spacer()
                            Text("\(purifier.activeCount) 条生效")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("净化")
                } footer: {
                    Text("按规则删掉正文里的网址、广告、求票尾巴，也能改章节标题。规则改了立刻生效，不用重开书。")
                }

                backupSection

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
                    Text("本地阅读器 · 数据保存在本机；可用备份文件导出 / 导入，开启 iCloud 后在同一 Apple ID 的设备间同步。")
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
            .sheet(isPresented: $showWebDAV) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("服务器地址", text: $davServer)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            TextField("用户名", text: $davUser)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            SecureField("密码", text: $davPass)
                        } footer: {
                            Text("例如 Nextcloud：https://dav.example.com/remote.php/dav/files/用户名。地址、账号密码只存在本机。")
                        }

                        Section {
                            Button {
                                saveWebDAV()
                            } label: {
                                HStack {
                                    Spacer()
                                    if dav.busy {
                                        ProgressView()
                                    } else {
                                        Text("保存并测试连接")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(dav.busy)

                            if dav.configured {
                                Button(role: .destructive) {
                                    dav.clearConfig()
                                    davMessage = "已清除 WebDAV 配置。"
                                } label: {
                                    Label("清除配置", systemImage: "trash")
                                }
                            }

                            if let davMessage {
                                Text(davMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("WebDAV 备份")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showWebDAV = false }
                        }
                    }
                }
            }
            .alert("字体", isPresented: Binding(
                get: { fontMessage != nil },
                set: { if $0 == false { fontMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(fontMessage ?? "")
            }
            .alert("备份", isPresented: Binding(
                get: { backupMessage != nil },
                set: { if $0 == false { backupMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(backupMessage ?? "")
            }
        }
    }

    private var backupSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: backup.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                    .foregroundStyle(backup.iCloudAvailable ? AppTheme.accent : AppTheme.secondary)
                Text(backup.iCloudAvailable ? "iCloud 已连接" : "iCloud 不可用")
                Spacer()
                Text(backup.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? "还没同步过")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                exportBackup()
            } label: {
                Label("导出备份文件", systemImage: "square.and.arrow.up")
            }

            Button {
                importBackup()
            } label: {
                Label("从备份恢复", systemImage: "arrow.down.circle")
            }

            if backup.iCloudAvailable {
                Button {
                    backup.pushToICloud()
                    backupMessage = "已同步到 iCloud。"
                } label: {
                    Label("立即同步到 iCloud", systemImage: "icloud.and.arrow.up")
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: dav.configured ? "externaldrive.fill" : "externaldrive")
                    .foregroundStyle(dav.configured ? AppTheme.accent : AppTheme.secondary)
                Text(dav.configured ? "WebDAV 已配置" : "WebDAV 未配置")
                Spacer()
                if let t = dav.lastSyncedAt {
                    Text(t.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                davServer = dav.server
                davUser = dav.username
                davPass = dav.password
                davMessage = nil
                showWebDAV = true
            } label: {
                Label(dav.configured ? "WebDAV 设置" : "配置 WebDAV", systemImage: "internaldrive")
            }

            if dav.configured {
                Button {
                    uploadToWebDAV()
                } label: {
                    Label("上传备份到 WebDAV", systemImage: "arrow.up.circle")
                }

                Button {
                    restoreFromWebDAV()
                } label: {
                    Label("从 WebDAV 恢复", systemImage: "arrow.down.circle")
                }
            }
        } header: {
            Text("备份与同步")
        } footer: {
            Text("备份包含书架、阅读进度、书签、书源、净化规则、阅读统计、设置和字体；书籍本体不进备份，需通过「文件」App 另行拷贝。iCloud 容器拿不到时可用 WebDAV 或备份文件。")
        }
    }

    private func importFont() {
        DocumentPickerHost.present(contentTypes: PickTypes.fonts, allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            Task {
                let message = fonts.add(url)
                try? await Task.sleep(nanoseconds: 350_000_000)
                fontMessage = message
            }
        }
    }

    private func exportBackup() {
        do {
            let url = try backup.exportBackup()
            DocumentPickerHost.presentExport(url: url) { _ in }
        } catch {
            backupMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importBackup() {
        DocumentPickerHost.present(contentTypes: PickTypes.backup, allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            Task { @MainActor in
                do {
                    try backup.restore(from: url)
                    backup.reloadAllStores(shelf: shelf)
                    backupMessage = "恢复完成，书架、进度和书源已还原。"
                } catch {
                    backupMessage = "恢复失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func saveWebDAV() {
        dav.saveConfig(server: davServer, username: davUser, password: davPass)
        Task { @MainActor in
            davMessage = await dav.testConnection()
        }
    }

    private func uploadToWebDAV() {
        Task { @MainActor in
            do {
                let data = try backup.currentBackupData()
                try await dav.upload(backup: data, stamp: Date())
                backupMessage = "已上传到 WebDAV。"
            } catch {
                backupMessage = "WebDAV 上传失败：\(error.localizedDescription)"
            }
        }
    }

    private func restoreFromWebDAV() {
        Task { @MainActor in
            do {
                let data = try await dav.download()
                try backup.restore(data: data)
                backup.reloadAllStores(shelf: shelf)
                backupMessage = "已从 WebDAV 恢复，书架、进度和书源已还原。"
            } catch {
                backupMessage = "WebDAV 恢复失败：\(error.localizedDescription)"
            }
        }
    }

    private static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) (\(build))"
    }
}
