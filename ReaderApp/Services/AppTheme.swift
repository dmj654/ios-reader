//
//  AppTheme.swift
//  ReaderApp
//
//  全局视觉系统：极简卡片式、iOS 原生工具风、低饱和冷色调。
//  - 大面积冷灰留白背景，白色大圆角卡片（深色下为冷灰抬升层）
//  - 细描边 + 弱阴影，低干扰
//  - 低饱和石板蓝强调色，简约线性图标
//  - 阅读页主题色保持独立，不被这里的界面配色覆盖
//

import SwiftUI
import UIKit

enum AppTheme {

    // MARK: - 配色（浅深自适应）

    /// 页面冷灰底色（大面积留白）
    static let background = dynamic(
        light: rgb(0.957, 0.965, 0.976),
        dark: rgb(0.063, 0.075, 0.090)
    )

    /// 卡片底色
    static let card = dynamic(
        light: .white,
        dark: rgb(0.102, 0.125, 0.149)
    )

    /// 细描边
    static let stroke = dynamic(
        light: rgb(0, 0, 0, alpha: 0.07),
        dark: rgb(1, 1, 1, alpha: 0.10)
    )

    /// 弱阴影（深色下接近透明，避免发灰发光）
    static let shadow = dynamic(
        light: rgb(0, 0, 0, alpha: 0.06),
        dark: .clear
    )

    /// 主文字（slate-800 / 冷白）
    static let primary = dynamic(
        light: rgb(0.118, 0.161, 0.231),
        dark: rgb(0.902, 0.925, 0.945)
    )

    /// 次要文字（slate-500 / 冷灰蓝）
    static let secondary = dynamic(
        light: rgb(0.392, 0.455, 0.545),
        dark: rgb(0.663, 0.706, 0.753)
    )

    /// 弱化文字
    static let tertiary = dynamic(
        light: rgb(0.580, 0.620, 0.670),
        dark: rgb(0.420, 0.471, 0.522)
    )

    /// 强调色：低饱和石板蓝（深色下提亮一档）
    static let accent = dynamic(
        light: rgb(0.357, 0.486, 0.600),
        dark: rgb(0.561, 0.706, 0.800)
    )

    /// 强调色浅底
    static let accentSoft = dynamic(
        light: rgb(0.357, 0.486, 0.600, alpha: 0.12),
        dark: rgb(0.561, 0.706, 0.800, alpha: 0.18)
    )

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

    // MARK: - 工具

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
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
