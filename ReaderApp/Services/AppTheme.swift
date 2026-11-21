//
//  AppTheme.swift
//  ReaderApp
//
//  全局视觉系统：极简卡片式、iOS 原生工具风、低饱和冷色调。
//  - 大面积冷灰留白背景，白色大圆角卡片
//  - 细描边 + 弱阴影，低干扰
//  - 低饱和石板蓝强调色，简约线性图标
//  - 阅读页主题色保持独立，不被这里的界面配色覆盖
//

import SwiftUI

enum AppTheme {

    // MARK: - 配色

    /// 页面冷灰底色（大面积留白）
    static let background = Color(red: 0.957, green: 0.965, blue: 0.976)

    /// 卡片底色
    static let card = Color.white

    /// 细描边
    static let stroke = Color.black.opacity(0.07)

    /// 弱阴影
    static let shadow = Color.black.opacity(0.06)

    /// 主文字（ slate-800 ）
    static let primary = Color(red: 0.118, green: 0.161, blue: 0.231)

    /// 次要文字（ slate-500 ）
    static let secondary = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// 弱化文字
    static let tertiary = Color(red: 0.580, green: 0.620, blue: 0.670)

    /// 强调色：低饱和石板蓝
    static let accent = Color(red: 0.357, green: 0.486, blue: 0.600)

    /// 强调色浅底
    static let accentSoft = accent.opacity(0.12)

    // MARK: - 圆角

    static let radiusCard: CGFloat = 16
    static let radiusInner: CGFloat = 12
    static let radiusChip: CGFloat = 20

    // MARK: - 阴影

    static let cardShadow: Shadow = Shadow(
        color: shadow,
        radius: 10,
        x: 0,
        y: 2
    )

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

extension View {

    /// 统一卡片：白底、大圆角、细描边、弱阴影
    func appCard(radius: CGFloat = AppTheme.radiusCard) -> some View {
        self
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 0.6)
            )
            .shadow(
                color: AppTheme.cardShadow.color,
                radius: AppTheme.cardShadow.radius,
                x: AppTheme.cardShadow.x,
                y: AppTheme.cardShadow.y
            )
    }

    /// 磨砂毛玻璃导航 / 工具条背景
    func glassBar() -> some View {
        self.background(.ultraThinMaterial)
    }
}
