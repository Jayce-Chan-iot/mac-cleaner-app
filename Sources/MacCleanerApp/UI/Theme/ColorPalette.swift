import SwiftUI

/// 统一的色板和状态映射
enum ColorPalette {
    /// 按类别返回颜色
    static func color(for category: FileItem.FileCategory) -> Color {
        switch category {
        case .image: return Color(hex: "00F5A0")
        case .video: return Color(hex: "00D4AA")
        case .document: return Color(hex: "00A8FF")
        case .audio: return Color(hex: "7B61FF")
        case .archive: return Color(hex: "C44DFF")
        case .application: return Color(hex: "FF6B81")
        case .code: return Color(hex: "FFA502")
        case .other: return Color(hex: "8888A0")
        }
    }

    /// 安全级别颜色
    static func color(for level: JunkCategory.SafetyLevel) -> Color {
        switch level {
        case .safe: return Color(hex: "2ED573")
        case .caution: return Color(hex: "FFA502")
        case .expert: return Color(hex: "FF4757")
        }
    }

    /// Sunburst 色阶（用于逐层展示）
    static let sunburstPalette: [Color] = AppTheme.sunburstGradient

    /// 大小分布色阶
    static let sizeGradient: [Color] = [
        Color(hex: "00F5A0"),  // < 10 MB
        Color(hex: "00D4AA"),  // 10-100 MB
        Color(hex: "00A8FF"),  // 100-500 MB
        Color(hex: "7B61FF"),  // 500 MB - 1 GB
        Color(hex: "C44DFF")   // > 1 GB
    ]

    /// 文件大小对应颜色
    static func color(forFileSize size: Int64) -> Color {
        switch size {
        case 0..<10_000_000: return sizeGradient[0]        // < 10 MB
        case 10_000_000..<100_000_000: return sizeGradient[1]  // 10-100 MB
        case 100_000_000..<500_000_000: return sizeGradient[2]  // 100-500 MB
        case 500_000_000..<1_000_000_000: return sizeGradient[3]  // 500 MB-1 GB
        default: return sizeGradient[4]                      // > 1 GB
        }
    }
}
