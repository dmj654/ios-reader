//
//  ReaderChrome.swift
//  ReaderApp
//
//  阅读页统一工具条（v0.9）
//  - 悬浮胶囊：左右内缩 16、高 44、圆角 22、.ultraThinMaterial + 0.5pt 描边
//  - 图标统一 17pt 线性、触控区 44×44
//  - 小说页和漫画页共用同一套尺寸，只用明暗区分主题
//

import SwiftUI

enum ReaderChromeMetrics {
    static let horizontalInset: CGFloat = 16
    static let topGap: CGFloat = 8
    static let bottomGap: CGFloat = 16
    static let height: CGFloat = 44
    static let radius: CGFloat = 22
    static let iconSize: CGFloat = 17
}

/// 胶囊底板
struct ReaderCapsule<Content: View>: View {
    let dark: Bool
    let content: Content

    init(dark: Bool, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        content
            .frame(height: ReaderChromeMetrics.height)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// 胶囊里的线性图标按钮
struct ChromeIconButton: View {
    let systemName: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ReaderChromeMetrics.iconSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: ReaderChromeMetrics.height, height: ReaderChromeMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 胶囊里的细进度滑轨（可拖动跳页）
struct ChromeProgressTrack: View {
    @Binding var fraction: Double
    var tint: Color = .primary
    var onCommit: () -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let knob: CGFloat = dragging ? 13 : 9

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.20))
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(3, width * fraction), height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(tint)
                    .frame(width: knob, height: knob)
                    .offset(x: min(width - knob, max(0, width * fraction - knob / 2)))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: ReaderChromeMetrics.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        fraction = min(1, max(0, value.location.x / width))
                    }
                    .onEnded { value in
                        dragging = false
                        fraction = min(1, max(0, value.location.x / width))
                        onCommit()
                    }
            )
        }
        .frame(height: ReaderChromeMetrics.height)
    }
}
