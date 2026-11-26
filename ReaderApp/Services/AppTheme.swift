//
//  AppTheme.swift
//  ReaderApp
//
//  全局视觉系统（第三版）：iOS 系统底 + 悬浮毛玻璃导航。
//  - 页面 #F2F2F7，内容白卡，文字近黑，单一主色 #3390EC
//  - 玻璃只给两层：底部 tab 与阅读工具条；其余一律不透明
//  - 阅读页纸色独立，不进系统配色
//

import SwiftUI
import UIKit

enum AppTheme {

    // MARK: - 配色（浅深自适应）

    /// 页面底色（iOS 分组灰）
    static let background = dynamic(
        light: hex(0xF2F2F7),
        dark: hex(0x0B0F14)
    )

    /// 卡片底色
    static let card = dynamic(
        light: hex(0xFFFFFF),
        dark: hex(0x141A22)
    )

    /// 细描边
    static let stroke = dynamic(
        light: hex(0x3C3C43, alpha: 0.12),
        dark: hex(0xFFFFFF, alpha: 0.09)
    )

    /// 弱阴影
    static let shadow = dynamic(
        light: hex(0x121A2C, alpha: 0.10),
        dark: .clear
    )

    /// 主文字
    static let primary = dynamic(
        light: hex(0x121216),
        dark: hex(0xEDEDF0)
    )

    /// 次要文字
    static let secondary = dynamic(
        light: hex(0x6E6E76),
        dark: hex(0xA7ADB6)
    )

    /// 弱化文字
    static let tertiary = dynamic(
        light: hex(0xA0A0A8),
        dark: hex(0x6B7280)
    )

    /// 强调色（唯一蓝）
    static let accent = dynamic(
        light: hex(0x3390EC),
        dark: hex(0x4CA6F0)
    )

    /// 强调色浅底
    static let accentSoft = dynamic(
        light: hex(0x3390EC, alpha: 0.12),
        dark: hex(0x4CA6F0, alpha: 0.20)
    )

    /// 阅读页纸色
    static let paper = dynamic(
        light: hex(0xFAF7F0),
        dark: hex(0x14110D)
    )

    /// 封面墨色
    static let inkCover = Color(uiColor: hex(0x1B2A3A))

    /// 封面纸色
    static let paperCover = dynamic(
        light: hex(0xE8E6E0),
        dark: hex(0xD9D5CC)
    )

    /// 朱砂印
    static let seal = Color(uiColor: hex(0xB4402C))

    /// 未选中的 tab 图标
    static let tabInactive = dynamic(
        light: hex(0x8A8A90),
        dark: hex(0x7D8B99)
    )

    // MARK: - 圆角

    static let radiusCard: CGFloat = 16
    static let radiusInner: CGFloat = 12
    static let radiusChip: CGFloat = 22

    // MARK: - 玻璃

    /// 底栏 / 工具条高度
    static let glassHeight: CGFloat = 64
    /// 左右内缩
    static let glassInset: CGFloat = 16
    /// 离底距离
    static let glassBottom: CGFloat = 12
    /// 玻璃圆角
    static let glassRadius: CGFloat = 24
    /// 内容需要给玻璃让出的高度（含阴影余量）
    static let tabBarReserve: CGFloat = glassHeight + glassBottom + 16

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

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension View {

    /// 统一卡片：白底、圆角、细描边、弱阴影
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

    /// 贴边的磨砂条（内部底部筛选栏用），不做圆角也不做外阴影
    func glassBar() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppTheme.stroke)
                    .frame(height: 0.5)
            }
    }
}
