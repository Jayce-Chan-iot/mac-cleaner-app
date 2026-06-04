import Foundation

/// 垃圾文件分类，按安全级别组织
enum JunkCategory: Identifiable, CaseIterable {
    // MARK: - 🟢 可安全清理
    case systemCache
    case appCache
    case browserCache
    case logs
    case trashBin

    // MARK: - 🟡 建议检查
    case xcodeJunk
    case mailAttachments
    case oldDownloads
    case iosBackups

    // MARK: - 🔴 需专家检查
    case homebrewCache
    case dockerLeftovers
    case devPackageCache

    var id: String { displayName }

    /// 所属安全级别
    var safetyLevel: SafetyLevel {
        switch self {
        case .systemCache, .appCache, .browserCache, .logs, .trashBin:
            return .safe
        case .xcodeJunk, .mailAttachments, .oldDownloads, .iosBackups:
            return .caution
        case .homebrewCache, .dockerLeftovers, .devPackageCache:
            return .expert
        }
    }

    var displayName: String {
        switch self {
        case .systemCache: return "系统缓存"
        case .appCache: return "应用缓存"
        case .browserCache: return "浏览器缓存"
        case .logs: return "日志文件"
        case .trashBin: return "废纸篓"
        case .xcodeJunk: return "Xcode 垃圾"
        case .mailAttachments: return "邮件附件"
        case .oldDownloads: return "旧下载文件"
        case .iosBackups: return "iOS 备份"
        case .homebrewCache: return "Homebrew 缓存"
        case .dockerLeftovers: return "Docker 残留"
        case .devPackageCache: return "开发包缓存"
        }
    }

    var iconName: String {
        switch self {
        case .systemCache: return "gearshape.2"
        case .appCache: return "app.badge"
        case .browserCache: return "safari"
        case .logs: return "doc.text.magnifyingglass"
        case .trashBin: return "trash"
        case .xcodeJunk: return "hammer"
        case .mailAttachments: return "paperclip"
        case .oldDownloads: return "arrow.down.circle.dotted"
        case .iosBackups: return "iphone.gen3"
        case .homebrewCache: return "mug"
        case .dockerLeftovers: return "shippingbox"
        case .devPackageCache: return "square.stack.3d.up"
        }
    }

    var description: String {
        switch self {
        case .systemCache: return "macOS 系统产生的临时文件和缓存"
        case .appCache: return "第三方应用产生的缓存数据"
        case .browserCache: return "Safari、Chrome 等浏览器的缓存文件"
        case .logs: return "系统和应用的日志输出文件"
        case .trashBin: return "废纸篓中尚未永久删除的文件"
        case .xcodeJunk: return "DerivedData、模拟器缓存、旧版本备份"
        case .mailAttachments: return "邮件应用下载的附件备份"
        case .oldDownloads: return "下载文件夹中可删除的安装包和临时文件"
        case .iosBackups: return "旧 iOS 设备通过 Finder 创建的备份"
        case .homebrewCache: return "Homebrew 下载的预编译包和源码缓存"
        case .dockerLeftovers: return "Docker 容器、镜像和卷的残留文件"
        case .devPackageCache: return "npm/Yarn/Cargo/CocoaPods 等包管理缓存"
        }
    }

    /// 安全级别枚举
    enum SafetyLevel: String, CaseIterable, Identifiable {
        case safe = "🟢 可安全清理"
        case caution = "🟡 建议检查"
        case expert = "🔴 需专家检查"

        var id: String { rawValue }
        var colorName: String {
            switch self {
            case .safe: return "green"
            case .caution: return "yellow"
            case .expert: return "red"
            }
        }
    }
}
