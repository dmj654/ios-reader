//
//  GlassKit.swift
//  ReaderApp
//
//  悬浮毛玻璃导航层：
//  - GlassPanel：.ultraThinMaterial + 白 70% 渐变 + 1pt 内高光 + 外阴影
//  - AmbientGlow：屏幕底部的蓝紫环境光，玻璃才有东西可模糊
//  - FloatingTabBar：离底 12、左右 16、高 64、圆角 24 的四段导航
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, shelf, discover, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "今日"
        case .shelf: return "书架"
        case .discover: return "发现"
        case .search: return "搜索"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "book"
        case .shelf: return "square.grid.2x2"
        case .discover: return "safari"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - 玻璃底板

struct GlassPanelModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.12 : 0.70),
                                    Color.white.opacity(scheme == .dark ? 0.04 : 0.44)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(scheme == .dark ? 0.14 : 0.72),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.50 : 0.16),
                radius: 22,
                x: 0,
                y: 14
            )
    }
}

extension View {
    func glassPanel(radius: CGFloat = AppTheme.glassRadius) -> some View {
        modifier(GlassPanelModifier(radius: radius))
    }
}

// MARK: - 环境光

/// 屏幕底部的一层很淡的蓝紫光。纯白底上玻璃看起来只是白条，垫了这层才有折射与色偏。
struct AmbientGlow: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(uiColor: AppTheme.hex(0x3390EC)).opacity(0.34), .clear],
                center: UnitPoint(x: 0.18, y: 1.02),
                startRadius: 4,
                endRadius: 190
            )

            RadialGradient(
                colors: [Color(uiColor: AppTheme.hex(0x7B6EFF)).opacity(0.26), .clear],
                center: UnitPoint(x: 0.84, y: 1.05),
                startRadius: 6,
                endRadius: 200
            )

            RadialGradient(
                colors: [Color(uiColor: AppTheme.hex(0x50C8C8)).opacity(0.16), .clear],
                center: UnitPoint(x: 0.52, y: 1.06),
                startRadius: 4,
                endRadius: 150
            )

            LinearGradient(
                colors: [.clear, Color(uiColor: AppTheme.hex(0x3390EC)).opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .opacity(scheme == .dark ? 0.55 : 1)
        .allowsHitTesting(false)
    }
}

// MARK: - 底栏

struct FloatingTabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { item in
                Button {
                    guard tab != item else { return }
                    withAnimation(.snappy(duration: 0.22)) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 21, weight: .medium))
                            .symbolVariant(tab == item ? .fill : .regular)

                        Text(item.title)
                            .font(.system(size: 9.5, weight: tab == item ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab == item ? AppTheme.accent : AppTheme.tabInactive)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: AppTheme.glassHeight)
        .glassPanel()
        .padding(.horizontal, AppTheme.glassInset)
        .padding(.bottom, AppTheme.glassBottom)
    }
}
