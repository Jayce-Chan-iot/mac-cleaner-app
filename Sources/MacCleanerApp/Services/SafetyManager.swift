import Foundation

/// 安全管理器 —— 确保所有文件操作安全可控
/// 参考 PureMac 的白名单机制和 MacSift 的 trashItem 策略
actor SafetyManager {
    /// 受保护的路径前缀 —— 绝对不触碰这些目录
    private let protectedPaths: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/usr/lib",
        "/usr/libexec",
        "/usr/sbin",
        "/usr/share",
        "/usr/standalone",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/.DocumentRevisions-V100",
        "/.TemporaryItems",
        "/.Trashes"
    ]

    /// 关键系统文件扩展名，即使在其他位置也不删除
    private let systemExtensions: Set<String> = [
        "kext", "framework", "bundle", "dylib"
    ]

    /// 操作日志记录
    private(set) var operationLog: [SafetyLogEntry] = []

    /// 检查路径是否受保护
    nonisolated func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        for protected in protectedPaths {
            if path.hasPrefix(protected) {
                return true
            }
        }
        // 检查扩展名是否为系统关键文件
        if systemExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        return false
    }

    /// 安全地移动文件到废纸篓
    /// - Parameter urls: 待删除文件 URL 列表
    /// - Returns: 成功删除的文件数量
    @discardableResult
    func trashItems(_ urls: [URL]) async throws -> Int {
        var count = 0
        let fileManager = FileManager.default

        for url in urls {
            // 白名单检查
            guard !isProtected(url) else {
                log(.skipped(url, reason: "受保护的系统路径"))
                continue
            }

            // 文件存在性检查
            guard fileManager.fileExists(atPath: url.path) else {
                log(.skipped(url, reason: "文件不存在"))
                continue
            }

            do {
                var resultingItemURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingItemURL)
                count += 1
                log(.deleted(url, trashLocation: resultingItemURL as URL?))
            } catch {
                log(.failed(url, error: error.localizedDescription))
            }
        }

        return count
    }

    /// 获取操作日志
    func getLog() -> [SafetyLogEntry] {
        operationLog
    }

    /// 清除操作日志
    func clearLog() {
        operationLog.removeAll()
    }

    // MARK: - Private

    private func log(_ entry: SafetyLogEntry) {
        operationLog.append(entry)
    }
}

// MARK: - Safety Log

/// 安全操作日志条目
struct SafetyLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let url: URL
    let action: Action
    let detail: String?

    enum Action: String {
        case deleted = "已删除"
        case skipped = "已跳过"
        case failed = "失败"
    }

    init(action: Action, url: URL, detail: String?) {
        self.timestamp = Date()
        self.url = url
        self.action = action
        self.detail = detail
    }

    static func deleted(_ url: URL, trashLocation: URL?) -> SafetyLogEntry {
        SafetyLogEntry(action: .deleted, url: url, detail: "移到废纸篓")
    }

    static func skipped(_ url: URL, reason: String) -> SafetyLogEntry {
        SafetyLogEntry(action: .skipped, url: url, detail: reason)
    }

    static func failed(_ url: URL, error: String) -> SafetyLogEntry {
        SafetyLogEntry(action: .failed, url: url, detail: error)
    }
}
