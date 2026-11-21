//
//  HomeLayoutStore.swift
//  ReaderApp
//
//  主页布局持久化：顺序 / 显隐写入 Application Support/HomeLayout.json。
//  先写临时文件再原子替换，避免写一半断电把布局弄没。
//

import Foundation

final class HomeLayoutStore: ObservableObject {

    static let shared = HomeLayoutStore()

    @Published private(set) var layout: HomeLayout

    private let storeURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if fm.fileExists(atPath: base.path) == false {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        storeURL = base.appendingPathComponent("HomeLayout.json")
        layout = Self.load(from: storeURL)
    }

    /// 测试用：注入自定义持久化路径
    init(storeURL: URL) {
        self.storeURL = storeURL
        layout = Self.load(from: storeURL)
    }

    // MARK: - 读写

    private static func load(from url: URL) -> HomeLayout {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HomeLayout.self, from: data) else {
            return .default
        }
        return decoded.normalized()
    }

    /// 从磁盘重新读布局（恢复备份后调用）
    func reload() {
        layout = Self.load(from: storeURL)
    }

    private func save() {
        let payload = layout.normalized()
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let tmp = storeURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.removeItem(at: storeURL)
            try FileManager.default.moveItem(at: tmp, to: storeURL)
        } catch {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    // MARK: - 操作

    /// 拖动排序（仅作用于可见列表）
    func move(fromOffsets: IndexSet, toOffsets: Int) {
        layout.order.move(fromOffsets: fromOffsets, toOffsets: toOffsets)
        save()
    }

    /// 隐藏卡片：从可见列表移除，进入隐藏列表
    func hide(_ id: HomeCardID) {
        layout.order.removeAll { $0 == id }
        if layout.hidden.contains(id) == false {
            layout.hidden.append(id)
        }
        save()
    }

    /// 恢复卡片：从隐藏列表回到可见列表末尾
    func restore(_ id: HomeCardID) {
        layout.hidden.removeAll { $0 == id }
        if layout.order.contains(id) == false {
            layout.order.append(id)
        }
        save()
    }

    /// 恢复默认布局
    func resetDefaults() {
        layout = .default
        save()
    }
}
