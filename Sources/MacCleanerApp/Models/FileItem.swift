import Foundation

/// 文件系统条目模型，表示扫描到的单个文件或目录
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileExtension: String
    let size: Int64          // 字节数
    let modificationDate: Date?
    let lastAccessDate: Date?
    let creationDate: Date?
    let isDirectory: Bool
    let fileType: FileCategory

    /// 格式化的文件大小字符串（如 "2.3 GB"）
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 文件类型枚举
    enum FileCategory: String, CaseIterable, Identifiable {
        case image = "图片"
        case video = "视频"
        case document = "文档"
        case audio = "音频"
        case archive = "压缩包"
        case application = "应用"
        case code = "代码"
        case other = "其他"

        var id: String { rawValue }

        /// SF Symbol 图标名
        var iconName: String {
            switch self {
            case .image: return "photo"
            case .video: return "film"
            case .document: return "doc.text"
            case .audio: return "music.note"
            case .archive: return "archivebox"
            case .application: return "app"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .other: return "questionmark.folder"
            }
        }

        /// 对应扩展名列表
        var extensions: [String] {
            switch self {
            case .image:
                return ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp",
                        "tiff", "tif", "raw", "cr2", "nef", "arw", "dng", "svg", "psd"]
            case .video:
                return ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
                        "3gp", "mts", "m2ts", "ts", "f4v", "asf"]
            case .document:
                return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                        "pages", "numbers", "keynote", "txt", "rtf", "md", "csv", "json", "xml", "plist"]
            case .audio:
                return ["mp3", "wav", "aac", "flac", "m4a", "wma", "ogg", "aiff",
                        "alac", "caf", "ac3"]
            case .archive:
                return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg",
                        "iso", "pkg", "tgz"]
            case .application:
                return ["app", "exe", "apk", "ipa"]
            case .code:
                return ["swift", "h", "m", "mm", "c", "cpp", "py", "js", "ts",
                        "java", "go", "rs", "rb", "sh", "html", "css", "scss", "sql",
                        "xcodeproj", "xcworkspace"]
            case .other:
                return []
            }
        }

        /// 根据文件扩展名判断类别
        static func from(extension ext: String) -> FileCategory {
            let lowercased = ext.lowercased()
            for category in FileCategory.allCases {
                if category.extensions.contains(lowercased) {
                    return category
                }
            }
            return .other
        }
    }
}

extension FileItem {
    /// 格式化修改日期为相对时间描述
    var relativeModificationDate: String {
        guard let date = modificationDate else { return "未知" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 是否为"旧文件"（超过指定天数未修改）
    func isOldFile(olderThan days: Int = 180) -> Bool {
        guard let date = modificationDate else { return false }
        return Date().timeIntervalSince(date) > TimeInterval(days * 86400)
    }
}
