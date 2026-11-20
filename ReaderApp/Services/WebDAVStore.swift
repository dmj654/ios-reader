//
//  WebDAVStore.swift
//  ReaderApp
//
//  WebDAV 备份通道：把备份包推到自己的 NAS / Nextcloud / ownCloud 等 WebDAV 服务器，
//  也能从远端拉回恢复。和 iCloud 互不依赖，哪条通走哪条。
//  - 配置只存在本机（UserDefaults），不上报第三方
//  - 冲突策略：按远端 meta 里的时间戳，新者覆盖，不做逐实体合并
//

import Foundation
import SwiftUI

@MainActor
final class WebDAVStore: ObservableObject {
    static let shared = WebDAVStore()

    @Published var server: String
    @Published var username: String
    @Published var password: String
    @Published var lastSyncedAt: Date?
    @Published var statusText: String?
    @Published var busy = false

    private let defaults = UserDefaults.standard

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    private init() {
        server = defaults.string(forKey: "webdav.server") ?? ""
        username = defaults.string(forKey: "webdav.user") ?? ""
        password = defaults.string(forKey: "webdav.pass") ?? ""
        lastSyncedAt = defaults.object(forKey: "webdav.lastSyncedAt") as? Date
    }

    var configured: Bool {
        URL(string: normalizedBase) != nil && username.isEmpty == false
    }

    private var normalizedBase: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty == false, s.hasPrefix("http") == false { s = "https://" + s }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var dirURL: URL? {
        guard let base = URL(string: normalizedBase) else { return nil }
        return base.appendingPathComponent("ReaderSync", isDirectory: true)
    }

    private var backupURL: URL? { dirURL?.appendingPathComponent("backup.readerbackup") }
    private var metaURL: URL? { dirURL?.appendingPathComponent("meta.json") }

    // MARK: - 配置

    func saveConfig(server: String, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
        defaults.set(server, forKey: "webdav.server")
        defaults.set(username, forKey: "webdav.user")
        defaults.set(password, forKey: "webdav.pass")
    }

    func clearConfig() {
        server = ""
        username = ""
        password = ""
        lastSyncedAt = nil
        statusText = nil
        defaults.removeObject(forKey: "webdav.server")
        defaults.removeObject(forKey: "webdav.user")
        defaults.removeObject(forKey: "webdav.pass")
        defaults.removeObject(forKey: "webdav.lastSyncedAt")
    }

    func markSynced(_ date: Date) {
        defaults.set(date, forKey: "webdav.lastSyncedAt")
        lastSyncedAt = date
    }

    // MARK: - 请求

    private func authorized(_ url: URL, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        let cred = Data("\(username):\(password)".utf8).base64EncodedString()
        req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func ensureDirectory() async throws {
        guard let dir = dirURL else { throw BackupError.message("WebDAV 地址不合法") }
        let (_, resp) = try await session.data(for: authorized(dir, method: "MKCOL"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 201 新建成功；405 表示目录已存在，都算通过
        if code != 201 && code != 405 && code >= 300 {
            throw BackupError.message("创建同步目录失败：\(code)")
        }
    }

    // MARK: - 对外操作

    /// 测试连接：建目录成功即认为账号密码和地址可用
    func testConnection() async -> String {
        busy = true
        defer { busy = false }
        do {
            try await ensureDirectory()
            statusText = "连接成功"
            return "连接成功"
        } catch {
            statusText = error.localizedDescription
            return statusText ?? "连接失败"
        }
    }

    /// 上传备份包和时间戳
    func upload(backup: Data, stamp: Date) async throws {
        guard let backupURL, let metaURL else { throw BackupError.message("WebDAV 地址不合法") }
        try await ensureDirectory()

        let meta = try JSONEncoder().encode(Meta(exportedAt: stamp))

        let (_, r1) = try await session.data(for: authorized(backupURL, method: "PUT", body: backup))
        let c1 = (r1 as? HTTPURLResponse)?.statusCode ?? 0
        guard c1 < 300 else { throw BackupError.message("备份上传失败：\(c1)") }

        let (_, r2) = try await session.data(for: authorized(metaURL, method: "PUT", body: meta))
        let c2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
        guard c2 < 300 else { throw BackupError.message("时间戳上传失败：\(c2)") }

        markSynced(stamp)
    }

    /// 读远端时间戳；没有备份时返回 nil
    func remoteMeta() async throws -> Meta? {
        guard let metaURL else { return nil }
        let (data, resp) = try await session.data(for: authorized(metaURL, method: "GET"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code < 300 else { throw BackupError.message("读取远端时间戳失败：\(code)") }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    /// 下载远端备份包
    func download() async throws -> Data {
        guard let backupURL else { throw BackupError.message("WebDAV 地址不合法") }
        let (data, resp) = try await session.data(for: authorized(backupURL, method: "GET"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code < 300 else { throw BackupError.message("下载备份失败：\(code)") }
        return data
    }

    struct Meta: Codable {
        let exportedAt: Date
    }
}
