//
//  StatsView.swift
//  ReaderApp
//
//  阅读统计面板（v1.8）
//  - 今日目标环 + 本周 / 本月 / 总计
//  - 13 周热力图、最近 7 天柱状
//  - 读得最多的书（带封面和进度）
//  - 复制文字摘要 / 清空统计
//

import SwiftUI
import UIKit

struct StatsView: View {
    @ObservedObject var store: ReadingStatsStore
    let books: [Book]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("stats.dailyGoalMinutes") private var goalMinutes: Int = 30

    @State private var toast: String?
    @State private var confirmReset = false

    private var summary: StatsSummary { store.summary(goalMinutes: goalMinutes) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    goalCard
                    metricRow
                    chipsRow
                    heatmapCard
                    weekCard
                    topBooksCard
                    actionsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("阅读统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 30)
                        .transition(.opacity)
                }
            }
            .alert("清空全部阅读统计？", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    store.reset()
                    show("统计已清空")
                }
            } message: {
                Text("时长、页数、连续天数会全部归零，无法恢复。书和书源不受影响。")
            }
        }
    }

    // MARK: - 卡片外观

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 今日目标

    private var goalCard: some View {
        card {
            HStack(alignment: .center, spacing: 18) {
                goalRing

                VStack(alignment: .leading, spacing: 4) {
                    Text("今日阅读")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(StatsFormat.duration(summary.todaySeconds))
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()

                    Text("\(summary.todayPages) 页 · 目标 \(goalMinutes) 分钟 · 已完成 \(summary.goalPercent)%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Menu {
                        ForEach([10, 15, 20, 30, 45, 60, 90], id: \.self) { minutes in
                            Button {
                                goalMinutes = minutes
                            } label: {
                                if minutes == goalMinutes {
                                    Label("\(minutes) 分钟", systemImage: "checkmark")
                                } else {
                                    Text("\(minutes) 分钟")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                            Text("调整每日目标")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.tint)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(0.001, summary.goalFraction))
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.85), AppTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(summary.goalPercent)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .animation(.easeOut(duration: 0.3), value: summary.goalFraction)
    }

    // MARK: - 三段数字

    private var metricRow: some View {
        HStack(spacing: 10) {
            metricCard("本周", StatsFormat.compact(summary.weekSeconds), deltaText)
            metricCard("本月", StatsFormat.compact(summary.monthSeconds), "\(summary.totalPages) 页累计")
            metricCard("总计", StatsFormat.compact(summary.totalSeconds), "\(summary.activeDays) 个阅读日")
        }
    }

    private var deltaText: String {
        let delta = summary.weekDelta
        if summary.lastWeekSeconds == 0, summary.weekSeconds == 0 { return "上周无记录" }
        if delta == 0 { return "与上周持平" }
        let text = StatsFormat.compact(abs(delta))
        return delta > 0 ? "比上周多 \(text)" : "比上周少 \(text)"
    }

    private func metricCard(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chipsRow: some View {
        HStack(spacing: 8) {
            chip(
                icon: "flame.fill",
                tint: .orange,
                text: summary.streak > 0 ? "连续 \(summary.streak) 天" : "还没连上"
            )
            chip(
                icon: "calendar",
                tint: .blue,
                text: "阅读 \(summary.activeDays) 天"
            )
            if summary.bestDaySeconds > 0 {
                chip(
                    icon: "trophy.fill",
                    tint: .yellow,
                    text: "最佳 \(StatsFormat.compact(summary.bestDaySeconds))"
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - 热力图

    private var heatmapCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("最近 13 周", trailing: "一格 = 一天")
                heatmapGrid
                legend
            }
        }
    }

    private let heatCell: CGFloat = 16
    private let heatGap: CGFloat = 5

    private var heatmapGrid: some View {
        let columns = store.heatmap(weeks: 13)
        return HStack(alignment: .top, spacing: heatGap) {
            VStack(alignment: .trailing, spacing: heatGap) {
                Text("一").font(.system(size: 9)).foregroundStyle(.tertiary).frame(height: heatCell)
                ForEach(1..<7, id: \.self) { _ in
                    Text("").frame(height: heatCell)
                }
                Text("日").font(.system(size: 9)).foregroundStyle(.tertiary).frame(height: heatCell)
            }
            .frame(width: 10)

            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: heatGap) {
                    ForEach(column) { cell in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(cell.future ? Color.clear : heatColor(cell.seconds))
                            .frame(width: heatCell, height: heatCell)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func heatColor(_ seconds: Int) -> Color {
        if seconds <= 0 { return Color.primary.opacity(0.06) }
        if seconds < 300 { return AppTheme.accent.opacity(0.28) }
        if seconds < 900 { return AppTheme.accent.opacity(0.45) }
        if seconds < 1800 { return AppTheme.accent.opacity(0.62) }
        if seconds < 3600 { return AppTheme.accent.opacity(0.82) }
        return AppTheme.accent
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            ForEach([0, 200, 600, 1500, 3000, 6000], id: \.self) { value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(heatColor(value))
                    .frame(width: 10, height: 10)
            }
            Text("多")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(StatsFormat.duration(summary.monthSeconds) + " / 本月")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 最近 7 天

    private var weekCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("最近 7 天", trailing: StatsFormat.duration(summary.weekSeconds) + " 本周")
                weekBars
            }
        }
    }

    private var weekBars: some View {
        let series = store.daysSeries(count: 7)
        let peak = max(1, series.map { $0.stat.seconds }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(series.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    Text(StatsFormat.compact(item.stat.seconds))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            index == series.count - 1
                                ? AppTheme.accent
                                : AppTheme.accent.opacity(0.35)
                        )
                        .frame(height: max(3, CGFloat(Double(item.stat.seconds) / Double(peak)) * 56))

                    Text(weekdayLetter(item.date))
                        .font(.system(size: 9))
                        .foregroundStyle(index == series.count - 1 ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96, alignment: .bottom)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    // MARK: - 排行榜

    private var topBooksCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("读得最多的书")

                let tops = store.topBooks(limit: 6)
                if tops.isEmpty {
                    Text("还没有统计数据。读几分钟，这里就会出现排行。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(tops) { item in
                        if let book = books.first(where: { $0.id == item.id }) {
                            bookRow(book: book, stat: item.stat)
                        } else {
                            removedBookRow(seconds: item.stat.seconds, pages: item.stat.pages)
                        }
                    }
                }
            }
        }
    }

    private func bookRow(book: Book, stat: BookStat) -> some View {
        HStack(spacing: 10) {
            StatCoverThumb(book: book)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(StatsFormat.duration(stat.seconds)) · \(stat.pages) 页 · 读了 \(max(1, stat.sessions)) 次")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.75))
                            .frame(width: max(1, geo.size.width * book.progress))
                    }
                }
                .frame(height: 3)
                .padding(.top, 1)
            }

            Text("\(Int((book.progress * 100).rounded()))%")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func removedBookRow(seconds: Int, pages: Int) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 28, height: 38)
                .overlay {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("已从书架移除")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(StatsFormat.duration(seconds)) · \(pages) 页")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - 操作

    private var actionsCard: some View {
        card {
            VStack(spacing: 0) {
                Button {
                    UIPasteboard.general.string = store.exportText(goalMinutes: goalMinutes)
                    show("统计摘要已复制到剪贴板")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                        Text("复制统计摘要")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 11)
                }

                Divider().padding(.leading, 30)

                Button {
                    confirmReset = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("清空统计")
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 小封面

struct StatCoverThumb: View {
    let book: Book

    @State private var cover: UIImage?

    var body: some View {
        Group {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [book.format.tintColor.opacity(0.9), book.format.tintColor.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: 28, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task {
            guard cover == nil else { return }
            if let disk = CoverStore.cached(bookID: book.id) {
                cover = disk
            }
        }
    }
}
