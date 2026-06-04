import SwiftUI

/// 应用主题配置 —— 暗色科技感 HUD 风格
enum AppTheme {
    // MARK: - Colors

    /// 主背景色
    static let background = Color(hex: "0A0A0F")
    /// 次级背景（卡片、面板）
    static let surface = Color(hex: "14141F")
    /// 表面高亮（选中、悬停）
    static let surfaceHighlight = Color(hex: "1E1E2E")
    /// 边框
    static let border = Color(hex: "2A2A3C")
    /// 主文本
    static let textPrimary = Color(hex: "E8E8F0")
    /// 次文本
    static let textSecondary = Color(hex: "8888A0")
    /// 强调色（青色）
    static let accent = Color(hex: "00D4AA")

    // MARK: - Gradients

    /// Sunburst 科技渐变：绿 → 青 → 蓝 → 紫
    static let sunburstGradient: [Color] = [
        Color(hex: "00F5A0"),
        Color(hex: "00D4AA"),
        Color(hex: "00A8FF"),
        Color(hex: "7B61FF"),
        Color(hex: "C44DFF")
    ]

    /// 危险/删除红色
    static let danger = Color(hex: "FF4757")
    /// 警告黄色
    static let warning = Color(hex: "FFA502")
    /// 安全绿色
    static let safe = Color(hex: "2ED573")
    /// 信息蓝色
    static let info = Color(hex: "1E90FF")

    // MARK: - Typography

    /// 大标题
    static func largeTitle(_ content: Text) -> some View {
        content
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(textPrimary)
    }

    /// 模块标题
    static func moduleTitle(_ content: Text) -> some View {
        content
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(textPrimary)
    }

    /// 正文
    static func bodyText(_ content: Text) -> some View {
        content
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundColor(textSecondary)
    }

    /// 数据数值
    static func valueText(_ content: Text) -> some View {
        content
            .font(.system(size: 36, weight: .bold, design: .monospaced))
            .foregroundColor(accent)
    }

    // MARK: - Card Style

    struct CardStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
    }

    /// 渐变边框卡片
    struct GradientBorderCard: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.5), AppTheme.border],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        modifier(AppTheme.CardStyle())
    }

    func gradientBorderCard() -> some View {
        modifier(AppTheme.GradientBorderCard())
    }
}

// MARK: - Hex Color Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
