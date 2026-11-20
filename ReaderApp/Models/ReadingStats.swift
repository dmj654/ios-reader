//
//  ReadingStats.swift
//  ReaderApp
//
//  阅读统计（v1.8）
//  - 按天聚合「时长 / 页数」，按书聚合阅读量
//  - 只有本机一份 JSON（Application Support/ReadingStats），不上传
//  - 阅读时按秒计时；连续 5 分钟没有翻页/点按就暂停计时，避免人走了还在涨
//

import Foundation
import SwiftUI
import UIKit

// MARK: - 数据结构

struct DayStat: Codable, Hashable {
    var seconds: Int = 0
    var pages: Int = 0
}

struct BookStat: Codable, Hashable {
    var seconds: Int = 0
    var pages: Int = 0
    var sessions: Int = 0
    var lastAt: Date = Date()
}

struct StatsPayload: Codable {
    var version: Int = 1
    var days: [String: DayStat] = [:]
    var books: [String: BookStat] = [:]
}

struct StatsSummary {
    var todaySeconds = 0
    var todayPages = 0
    var weekSeconds = 0
    var lastWeekSeconds = 0
    var monthSeconds = 0
    var totalSeconds = 0
    var totalPages = 0
    var activeDays = 0
    var streak = 0
    var bestDaySeconds = 0
    var bestDay: Date?
    var goalMinutes = 30

    var goalSeconds: Int { max(60, goalMinutes * 60) }
    var goalFraction: Double {
        guard todaySeconds > 0 else { return 0 }
        return min(1, Double(todaySeconds) / Double(goalSeconds))
    }
    var goalPercent: Int { Int((goalFraction * 100).rounded()) }
    var weekDelta: Int { weekSeconds - lastWeekSeconds }
}

/// 热力图格子
struct HeatCell: Identifiable {
    var id: Date { date }
    let date: Date
    let seconds: Int
    let future: Bool
}

/// 排行榜条目（单独建个结构，方便 SwiftUI 用 id 做差异更新）
struct TopBook: Identifiable {
    let id: UUID
    let stat: BookStat
}

// MARK: - 文案

enum StatsFormat {

    /// 「28 分钟」「2 小时 15 分」「不足 1 分钟」
    static func duration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0 分钟" }
        if seconds < 60 { return "不足 1 分钟" }
        let totalMinutes = seconds / 60
        if totalMinutes < 60 { return "\(totalMinutes) 分钟" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }

    /// 紧凑版，用在格子里
    static func compact(_ seconds: Int) -> String {
        if seconds <= 0 { return "0" }
        if seconds < 60 { return "\(seconds)秒" }
        let totalMinutes = seconds / 60
        if totalMinutes < 60 { return "\(totalMinutes)分" }
        let hours = Double(totalMinutes) / 60
        return String(format: "%.1f时", hours)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

// MARK: - 存储

/// 全局单例，所有调用都发生在主线程（SwiftUI 动作 / 主 RunLoop 计时器 / 主队列通知）
final class ReadingStatsStore: ObservableObject {

    static let shared = ReadingStatsStore()

    /// 保存到磁盘后自增，界面靠它刷新
    @Published private(set) var revision = 0
    /// 当前是否在计时（界面显示「正在计时」小圆点）
    @Published private(set) var isRecording = false

    private(set) var days: [String: DayStat] = [:]
    private(set) var books: [String: BookStat] = [:]

    private var session: UUID?
    private var timer: Timer?
    private var idleTicks = 0
    private var unsavedSeconds = 0
    private var flushItem: DispatchWorkItem?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    /// 连续这么久没有翻页 / 点按，就认为人走了，暂停计时
    private let idleLimit = 300
    /// 每攒够这么多秒就落盘一次
    private let flushEvery = 15

    private init() {
        load()
        observeAppLifecycle()
    }

    // MARK: 路径

    private var storeURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadingStats", isDirectory: true)
        if fm.fileExists(atPath: base.path) == false {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("stats.json")
    }

    // MARK: 读写

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let payload = try? JSONDecoder().decode(StatsPayload.self, from: data) else {
            days = [:]
            books = [:]
            return
        }
        days = payload.days
        books = payload.books
    }

    private func save() {
        let payload = StatsPayload(version: 1, days: days, books: books)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // 先写临时文件再替换，避免写一半断电把历史统计弄没
        let tmp = storeURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.removeItem(at: storeURL)
            try FileManager.default.moveItem(at: tmp, to: storeURL)
        } catch {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// 落盘并通知界面刷新
    func flush() {
        unsavedSeconds = 0
        save()
        revision &+= 1
    }

    // MARK: 日期

    static func dayKey(for date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private static func date(fromKey key: String) -> Date? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return Calendar.current.date(from: parts)
    }

    func stat(on date: Date) -> DayStat {
        days[ReadingStatsStore.dayKey(for: date)] ?? DayStat()
    }

    // MARK: 会话

    func beginSession(bookID: UUID) {
        if let current = session, current == bookID {
            noteActivity()
            return
        }
        if session != nil { endSession() }

        session = bookID
        idleTicks = 0
        isRecording = true

        let key = bookID.uuidString
        var stat = books[key] ?? BookStat()
        stat.sessions += 1
        stat.lastAt = Date()
        books[key] = stat

        startTimer()
    }

    func endSession() {
        guard session != nil else { return }
        stopTimer()
        flush()
        session = nil
        isRecording = false
        idleTicks = 0
    }

    /// 有活动（翻页 / 点按 / 打开面板）就重置空闲计时；pages > 0 时记页数
    func noteActivity(pages: Int = 0) {
        guard let session else { return }
        idleTicks = 0
        guard pages > 0 else { return }

        let dayKey = ReadingStatsStore.dayKey()
        var day = days[dayKey] ?? DayStat()
        day.pages += pages
        days[dayKey] = day

        let bookKey = session.uuidString
        var stat = books[bookKey] ?? BookStat()
        stat.pages += pages
        stat.lastAt = Date()
        books[bookKey] = stat

        flushSoon()
    }

    /// 页数变化后延后落盘，避免每翻一页写一次磁盘
    private func flushSoon() {
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flush()
        }
        flushItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    // MARK: 计时

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // 加到 common 模式，滚动列表时也不会被冻住
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard session != nil else { return }
        idleTicks += 1
        guard idleTicks <= idleLimit else { return }

        let dayKey = ReadingStatsStore.dayKey()
        var day = days[dayKey] ?? DayStat()
        day.seconds += 1
        days[dayKey] = day

        if let session {
            let key = session.uuidString
            var stat = books[key] ?? BookStat()
            stat.seconds += 1
            stat.lastAt = Date()
            books[key] = stat
        }

        unsavedSeconds += 1
        if unsavedSeconds >= flushEvery { flush() }
    }

    // MARK: App 前后台

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stopTimer()
            self.flush()
        }
        foregroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.session != nil else { return }
            self.idleTicks = 0
            self.startTimer()
        }
    }

    // MARK: 汇总

    func summary(goalMinutes: Int) -> StatsSummary {
        var summary = StatsSummary()
        summary.goalMinutes = max(1, goalMinutes)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayKey = ReadingStatsStore.dayKey(for: today)
        summary.todaySeconds = days[todayKey]?.seconds ?? 0
        summary.todayPages = days[todayKey]?.pages ?? 0

        // 本周从周一开始
        let weekday = calendar.component(.weekday, from: today) // 1 = 周日
        let offsetToMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offsetToMonday, to: today) ?? today

        var weekSeconds = 0
        var lastWeekSeconds = 0
        for index in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: index, to: monday) {
                weekSeconds += days[ReadingStatsStore.dayKey(for: date)]?.seconds ?? 0
                if let previous = calendar.date(byAdding: .day, value: -7, to: date) {
                    lastWeekSeconds += days[ReadingStatsStore.dayKey(for: previous)]?.seconds ?? 0
                }
            }
        }
        summary.weekSeconds = weekSeconds
        summary.lastWeekSeconds = lastWeekSeconds

        // 本月
        let monthParts = calendar.dateComponents([.year, .month], from: today)
        for (key, stat) in days {
            guard let date = ReadingStatsStore.date(fromKey: key) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            if parts.year == monthParts.year, parts.month == monthParts.month {
                summary.monthSeconds += stat.seconds
            }
        }

        // 总计 / 活跃天数 / 单日最佳
        for (key, stat) in days {
            summary.totalSeconds += stat.seconds
            summary.totalPages += stat.pages
            if stat.seconds >= 60 { summary.activeDays += 1 }
            if stat.seconds > summary.bestDaySeconds {
                summary.bestDaySeconds = stat.seconds
                summary.bestDay = ReadingStatsStore.date(fromKey: key)
            }
        }

        // 连续天数：今天还没读就从昨天往前数
        var streak = 0
        var cursor = today
        if (days[todayKey]?.seconds ?? 0) < 60 {
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        while true {
            let key = ReadingStatsStore.dayKey(for: cursor)
            let seconds = days[key]?.seconds ?? 0
            if seconds >= 60 {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            } else {
                break
            }
        }
        summary.streak = streak

        return summary
    }

    // MARK: 图表数据

    /// 最近 count 天（含今天），按时间正序
    func daysSeries(count: Int) -> [(date: Date, stat: DayStat)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(date: Date, stat: DayStat)] = []
        for index in stride(from: count - 1, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -index, to: today) {
                result.append((date, stat(on: date)))
            }
        }
        return result
    }

    /// 13 周热力图，每列一周（周一在最上）
    func heatmap(weeks: Int = 13) -> [[HeatCell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offsetToMonday = (weekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -offsetToMonday, to: today) ?? today
        let firstMonday = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMonday) ?? today

        var columns: [[HeatCell]] = []
        for column in 0..<weeks {
            var cells: [HeatCell] = []
            for row in 0..<7 {
                let date = calendar.date(byAdding: .day, value: column * 7 + row, to: firstMonday) ?? firstMonday
                let isFuture = date > today
                cells.append(
                    HeatCell(date: date, seconds: stat(on: date).seconds, future: isFuture)
                )
            }
            columns.append(cells)
        }
        return columns
    }

    /// 读得最多的书
    func topBooks(limit: Int = 6) -> [TopBook] {
        books
            .compactMap { key, stat -> TopBook? in
                guard let id = UUID(uuidString: key) else { return nil }
                return TopBook(id: id, stat: stat)
            }
            .sorted { $0.stat.seconds > $1.stat.seconds }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: 导出 / 清空

    func exportText(goalMinutes: Int) -> String {
        let summary = summary(goalMinutes: goalMinutes)
        var lines: [String] = []
        lines.append("本地阅读器 · 阅读统计")
        lines.append("生成于 \(StatsFormat.day(Date()))")
        lines.append("")
        lines.append("总计：\(StatsFormat.duration(summary.totalSeconds))，共 \(summary.totalPages) 页")
        lines.append("本月：\(StatsFormat.duration(summary.monthSeconds))")
        lines.append("本周：\(StatsFormat.duration(summary.weekSeconds))（上周 \(StatsFormat.duration(summary.lastWeekSeconds))）")
        lines.append("今日：\(StatsFormat.duration(summary.todaySeconds))，\(summary.todayPages) 页，目标 \(goalMinutes) 分钟（完成 \(summary.goalPercent)%）")
        lines.append("连续阅读：\(summary.streak) 天，累计 \(summary.activeDays) 个阅读日")

        if summary.bestDaySeconds > 0, let best = summary.bestDay {
            lines.append("单日最多：\(StatsFormat.duration(summary.bestDaySeconds))（\(StatsFormat.day(best))）")
        }

        let tops = topBooks(limit: 5)
        if tops.isEmpty == false {
            lines.append("")
            lines.append("读得最多的书：")
            for item in tops {
                lines.append("· \(StatsFormat.duration(item.stat.seconds))，\(item.stat.pages) 页")
            }
        }

        return lines.joined(separator: "\n")
    }

    func reset() {
        stopTimer()
        session = nil
        isRecording = false
        days = [:]
        books = [:]
        idleTicks = 0
        unsavedSeconds = 0
        save()
        revision &+= 1
    }
}
