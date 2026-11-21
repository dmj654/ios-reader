//
//  BackupStore.swift
//  ReaderApp
//
//  备份 / 恢复：书架、进度、书签、书源、净化规则、阅读统计、设置、字体清单。
//  - 本地备份：打成 .readerbackup（zip），存到「文件」App，换机再导入
//  - iCloud：同一 Apple ID 下自动双向同步小配置；容器拿不到时自动降级到备份文件
//  书籍本体（TXT/EPUB/PDF/CBZ）体积大，不进备份，需要通过「文件」App 另行拷贝。
//

import Foundation
import ZIPFoundation

enum BackupError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

final class BackupStore: ObservableObject {
    static let shared = BackupStore()

    @Published var iCloudAvailable = false
    @Published var lastSyncedAt: Date?
    @Published var statusText: String?
    @Published var busy = false

    private let fm = FileManager.default
    private let docsDir: URL
    private let appSupport: URL

    /// iCloud Drive 容器里的同步目录；拿不到容器时为 nil（侧载签名常见）
    private var iCloudSyncDir: URL? {
        guard let root = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return root.appendingPathComponent("ReaderSync", isDirectory: true)
    }

    private struct SyncMeta: Codable {
        let exportedAt: Date
    }

    private init() {
        docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        refreshAvailability()
    }

    /// 测试注入：使用临时目录作为沙盒，不触碰真实容器
    init(docsDir: URL, appSupport: URL) {
        self.docsDir = docsDir
        self.appSupport = appSupport
        refreshAvailability()
    }

    func refreshAvailability() {
        iCloudAvailable = iCloudSyncDir != nil
        lastSyncedAt = UserDefaults.standard.object(forKey: "backup.lastSyncedAt") as? Date
    }

    // MARK: - 收集要备份的内容

    private func collectEntries() -> [(name: String, data: Data)] {
        var entries: [(String, Data)] = []

        func addFile(_ name: String, url: URL) {
            guard let data = try? Data(contentsOf: url) else { return }
            entries.append((name, data))
        }

        addFile("bookshelf.json", url: docsDir.appendingPathComponent("bookshelf.json"))
        addFile("bookmarks.json", url: docsDir.appendingPathComponent("bookmarks.json"))
        addFile("sources.json", url: docsDir.appendingPathComponent("Sources").appendingPathComponent("sources.json"))
        addFile("purifiers.json", url: docsDir.appendingPathComponent("Purifiers.json"))
        addFile("stats.json", url: appSupport.appendingPathComponent("ReadingStats").appendingPathComponent("stats.json"))
        addFile("HomeLayout.json", url: appSupport.appendingPathComponent("HomeLayout.json"))

        // 设置与阅读位置快照（readpos- 是在线阅读进度，单独保留；同步时间戳不备份）
        let defaults = UserDefaults.standard
        var snapshot: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix("readpos-") == false, key != "backup.lastSyncedAt" else { continue }
            guard let safe = Self.jsonSafe(value) else { continue }
            snapshot[key] = safe
        }
        if let data = try? JSONSerialization.data(withJSONObject: snapshot) {
            entries.append(("settings.json", data))
        }

        // 字体文件（ttf / otf / ttc）
        let fontsDir = docsDir.appendingPathComponent("Fonts")
        if let names = try? fm.contentsOfDirectory(atPath: fontsDir.path) {
            for name in names {
                let ext = (name as NSString).pathExtension.lowercased()
                guard ["ttf", "otf", "ttc"].contains(ext) else { continue }
                if let data = try? Data(contentsOf: fontsDir.appendingPathComponent(name)) {
                    entries.append(("fonts/\(name)", data))
                }
            }
        }

        return entries
    }

    /// 只保留 JSONSerialization 可序列化的值；Data / 自定义对象等直接跳过。
    /// JSONSerialization 遇到不支持类型会抛 ObjC 异常，`try?` 拦不住，必须先过滤。
    private static func jsonSafe(_ value: Any) -> Any? {
        switch value {
        case let v as String: return v
        case let v as NSNumber: return v
        case let v as Bool: return v
        case let v as Int: return v
        case let v as Double: return v
        case let v as [Any]:
            return v.compactMap { jsonSafe($0) }
        case let v as [String: Any]:
            var out: [String: Any] = [:]
            for (key, inner) in v {
                if let safe = jsonSafe(inner) { out[key] = safe }
            }
            return out
        case is NSNull: return NSNull()
        default: return nil
        }
    }

    // MARK: - 打包

    private func makeBackup() throws -> (data: Data, stamp: Date) {
        var entries = collectEntries()
        let stamp = Date()
        let meta = SyncMeta(exportedAt: stamp)
        if let data = try? JSONEncoder().encode(meta) {
            entries.append(("meta.json", data))
        }
        let data = MiniZip.make(entries: entries)
        return (data, stamp)
    }

    /// 供 WebDAV / 其他通道直接拿备份二进制
    func currentBackupData() throws -> Data {
        try makeBackup().data
    }

    // MARK: - 本地备份 / 恢复

    /// 打包成 .readerbackup，返回临时文件路径（交给文件选择器导出）
    func exportBackup() throws -> URL {
        let made = try makeBackup()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let out = fm.temporaryDirectory
            .appendingPathComponent("ReaderBackup-\(formatter.string(from: made.stamp)).readerbackup")
        try? fm.removeItem(at: out)

        try made.data.write(to: out, options: .atomic)
        return out
    }

    /// 从二进制恢复（WebDAV 拉回的数据包走这里）
    func restore(data: Data) throws {
        let tmp = fm.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).readerbackup")
        try data.write(to: tmp, options: .atomic)
        defer { try? fm.removeItem(at: tmp) }
        try restore(from: tmp)
    }

    /// 从备份包恢复（本地导入 / iCloud 拉取共用）
    func restore(from url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let archive = Archive(url: url, accessMode: .read) else {
            throw BackupError.message("备份包打不开，可能文件损坏")
        }

        var files: [String: Data] = [:]
        for entry in archive where entry.type != .directory {
            var data = Data()
            do {
                _ = try archive.extract(entry) { chunk in data.append(chunk) }
            } catch {
                continue
            }
            files[entry.path] = data
        }

        guard files["meta.json"] != nil else {
            throw BackupError.message("这不是本 App 的备份包")
        }

        func write(_ name: String, to target: URL) {
            guard let data = files[name] else { return }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }

        write("bookshelf.json", to: docsDir.appendingPathComponent("bookshelf.json"))
        write("bookmarks.json", to: docsDir.appendingPathComponent("bookmarks.json"))
        write("sources.json", to: docsDir.appendingPathComponent("Sources").appendingPathComponent("sources.json"))
        write("purifiers.json", to: docsDir.appendingPathComponent("Purifiers.json"))
        write("stats.json", to: appSupport.appendingPathComponent("ReadingStats").appendingPathComponent("stats.json"))
        write("HomeLayout.json", to: appSupport.appendingPathComponent("HomeLayout.json"))

        // 字体文件
        for (path, data) in files where path.hasPrefix("fonts/") {
            let name = String(path.dropFirst("fonts/".count))
            guard name.isEmpty == false else { continue }
            let target = docsDir.appendingPathComponent("Fonts").appendingPathComponent(name)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }

        // 设置快照
        if let settingsData = files["settings.json"],
           let snapshot = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
            let defaults = UserDefaults.standard
            for (key, value) in snapshot {
                defaults.set(value, forKey: key)
            }
        }
    }

    // MARK: - iCloud 自动同步

    /// 把当前配置推到 iCloud（启动时、设置变更后可调用）
    func pushToICloud() {
        guard let dir = iCloudSyncDir else { return }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let made = try makeBackup()
            try made.data.write(to: dir.appendingPathComponent("backup.readerbackup"), options: .atomic)
            UserDefaults.standard.set(made.stamp, forKey: "backup.lastSyncedAt")
            lastSyncedAt = made.stamp
        } catch {
            statusText = "iCloud 上传失败：\(error.localizedDescription)"
        }
    }

    /// 启动时拉取：远端比本地新就恢复远端配置
    func pullFromICloud() {
        guard let dir = iCloudSyncDir else { return }
        let metaURL = dir.appendingPathComponent("meta.json")
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SyncMeta.self, from: metaData) else { return }

        let local = lastSyncedAt ?? .distantPast
        guard meta.exportedAt > local else { return }

        let backupURL = dir.appendingPathComponent("backup.readerbackup")
        do {
            try restore(from: backupURL)
            UserDefaults.standard.set(meta.exportedAt, forKey: "backup.lastSyncedAt")
            lastSyncedAt = meta.exportedAt
        } catch {
            statusText = "iCloud 恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: - WebDAV 自动同步

    /// 把当前配置推到 WebDAV 服务器
    func pushToWebDAV() {
        let web = WebDAVStore.shared
        Task { @MainActor in
            guard web.configured else { return }
            do {
                let made = try makeBackup()
                try await web.upload(backup: made.data, stamp: made.stamp)
            } catch {
                statusText = "WebDAV 上传失败：\(error.localizedDescription)"
            }
        }
    }

    /// 启动时拉取：远端比本地新就恢复远端配置
    func pullFromWebDAV() {
        let web = WebDAVStore.shared
        Task { @MainActor in
            guard web.configured else { return }
            do {
                guard let meta = try await web.remoteMeta() else { return }
                let local = web.lastSyncedAt ?? .distantPast
                guard meta.exportedAt > local else { return }
                let data = try await web.download()
                try restore(data: data)
                web.markSynced(meta.exportedAt)
            } catch {
                statusText = "WebDAV 恢复失败：\(error.localizedDescription)"
            }
        }
    }

    /// 导入备份后，让各仓库重新读盘
    @MainActor
    func reloadAllStores(shelf: BookshelfViewModel?) {
        shelf?.load()
        shelf?.loadBookmarks()
        shelf?.scan()
        SourceStore.shared.load()
        PurifierStore.shared.reload()
        ReadingStatsStore.shared.reload()
        HomeLayoutStore.shared.reload()
        FontStore.shared.refresh()
    }
}
