import Foundation

/// 垃圾文件识别引擎
/// 参考 PureMac 的 JunkCleaner 和 MacSift 的 FileScanner
actor JunkDetector {
    private let fileManager = FileManager.default
    private let safetyManager = SafetyManager()

    /// 预定义的垃圾文件扫描规则（UnifiedScanner 共享使用）
    /// 每个规则包含：JunkCategory、路径模板、文件匹配模式
    nonisolated let rules: [(JunkCategory, URL, String?)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        return [
            // MARK: 🟢 可安全清理
            (.systemCache, library.appendingPathComponent("Caches"), nil),
            (.systemCache, URL(fileURLWithPath: "/tmp"), nil),
            (.appCache, library.appendingPathComponent("Containers"), "*/Data/Library/Caches"),
            (.browserCache, library.appendingPathComponent("Safari/LocalStorage"), nil),
            (.browserCache, library.appendingPathComponent("Caches/com.apple.Safari"), nil),
            (.browserCache, library.appendingPathComponent("Caches/Google/Chrome"), nil),
            (.browserCache, library.appendingPathComponent("Caches/Mozilla/Firefox"), nil),
            (.logs, library.appendingPathComponent("Logs"), nil),
            (.logs, URL(fileURLWithPath: "/var/log"), nil),
            (.trashBin, home.appendingPathComponent(".Trash"), nil),

            // MARK: 🟡 建议检查
            (.xcodeJunk, library.appendingPathComponent("Developer/Xcode/DerivedData"), nil),
            (.xcodeJunk, library.appendingPathComponent("Developer/Xcode/Archives"), nil),
            (.xcodeJunk, library.appendingPathComponent("Developer/CoreSimulator/Caches"), nil),
            (.mailAttachments, library.appendingPathComponent("Containers/com.apple.mail"), "Data/Library/Mail Downloads"),
            (.oldDownloads, home.appendingPathComponent("Downloads"), nil),
            (.iosBackups, library.appendingPathComponent("Application Support/MobileSync/Backup"), nil),

            // MARK: 🔴 需专家检查
            (.homebrewCache, library.appendingPathComponent("Caches/Homebrew"), nil),
            (.dockerLeftovers, library.appendingPathComponent("Containers/com.docker.docker"), nil),
            (.devPackageCache, library.appendingPathComponent("Caches/CocoaPods"), nil),
            (.devPackageCache, home.appendingPathComponent(".npm/_cacache"), nil),
            (.devPackageCache, home.appendingPathComponent(".cargo/registry/cache"), nil),
            (.devPackageCache, library.appendingPathComponent("Caches/Yarn"), nil),
        ]
    }()

    /// 执行垃圾文件扫描
    /// - Parameter progressHandler: 进度回调 (current, total, currentCategory)
    /// - Returns: 按 JunkCategory 分组的垃圾文件
    func scanJunk(
        progressHandler: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async throws -> [JunkCategory: [FileItem]] {
        var results: [JunkCategory: [FileItem]] = [:]

        for (index, (category, baseURL, pattern)) in rules.enumerated() {
            progressHandler?(index + 1, rules.count, category.displayName)

            // 检查路径是否存在
            guard fileManager.fileExists(atPath: baseURL.path) else {
                results[category] = []
                continue
            }

            do {
                let files = try await scanCategory(
                    category: category,
                    at: baseURL,
                    pattern: pattern
                )
                results[category] = files
            } catch {
                results[category] = []
            }
        }

        progressHandler?(rules.count, rules.count, "扫描完成")
        return results
    }

    /// 获取所有可扫描的垃圾文件总数大小
    func calculateTotalJunkSize(_ junkFiles: [JunkCategory: [FileItem]]) -> Int64 {
        junkFiles.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    /// 获取制定安全级别的垃圾类别
    func categories(for level: JunkCategory.SafetyLevel) -> [JunkCategory] {
        JunkCategory.allCases.filter { $0.safetyLevel == level }
    }

    /// 检查单个文件 URL 是否匹配指定规则（UnifiedScanner 流式模式使用）
    nonisolated func matchesRule(url: URL, baseURL: URL, pattern: String?) -> Bool {
        guard url.path.hasPrefix(baseURL.path) else { return false }
        guard let pattern = pattern else { return true }

        let patternComponents = pattern.components(separatedBy: "/")
        let baseCount = baseURL.pathComponents.count
        let urlComponents = url.pathComponents

        var pi = 0
        var ui = baseCount

        while pi < patternComponents.count && ui < urlComponents.count {
            if patternComponents[pi] == "*" {
                pi += 1
                if pi >= patternComponents.count { return true }
                while ui < urlComponents.count && urlComponents[ui] != patternComponents[pi] {
                    ui += 1
                }
                if ui >= urlComponents.count { return false }
            } else if patternComponents[pi] != urlComponents[ui] {
                return false
            }
            pi += 1
            ui += 1
        }
        return pi >= patternComponents.count
    }

    // MARK: - Private

    private func scanCategory(
        category: JunkCategory,
        at url: URL,
        pattern: String?
    ) async throws -> [FileItem] {
        var results: [FileItem] = []

        if let pattern = pattern {
            // 使用 Glob 模式匹配
            let patternURL = url.appendingPathComponent(pattern)
            let patternComponents = patternURL.pathComponents

            // 找到通配符位置
            if let wildcardIndex = patternComponents.firstIndex(of: "*") {
                let basePath = patternComponents[0..<wildcardIndex].joined(separator: "/")
                let baseSearchURL = URL(fileURLWithPath: "/" + basePath)

                guard fileManager.fileExists(atPath: baseSearchURL.path) else {
                    return results
                }

                // 遍历容器目录
                let contents = try fileManager.contentsOfDirectory(
                    at: baseSearchURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                for container in contents {
                    let isDir = try container.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                    if isDir {
                        let remainingPath = patternComponents[(wildcardIndex + 1)...].joined(separator: "/")
                        let targetURL = container.appendingPathComponent(remainingPath)

                        if fileManager.fileExists(atPath: targetURL.path) {
                            let files = try await enumerateJunkFiles(in: targetURL, category: category)
                            results.append(contentsOf: files)
                        }
                    }
                }
            }
        } else {
            // 直接扫描目录
            results = try await enumerateJunkFiles(in: url, category: category)
        }

        return results
    }

    private func enumerateJunkFiles(
        in directoryURL: URL,
        category: JunkCategory,
        maxDepth: Int = 5
    ) async throws -> [FileItem] {
        var results: [FileItem] = []

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return results
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return results
        }

        // 收集所有 URL（NSEnumerator 不支持 async 迭代）
        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
            .filter { url in
                let depth = url.path.components(separatedBy: "/").count
                    - directoryURL.path.components(separatedBy: "/").count
                return depth <= maxDepth
            }

        for fileURL in allURLs {
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
                    .contentAccessDateKey, .creationDateKey
                ])

                guard values.isDirectory != true else { continue }

                let size = Int64(values.fileSize ?? 0)
                let modDate = values.contentModificationDate
                let accessDate = values.contentAccessDate
                let createDate = values.creationDate
                let ext = fileURL.pathExtension
                let fileCategory = FileItem.FileCategory.from(extension: ext)

                let item = FileItem(
                    url: fileURL,
                    fileName: fileURL.lastPathComponent,
                    fileExtension: ext,
                    size: size,
                    modificationDate: modDate,
                    lastAccessDate: accessDate,
                    creationDate: createDate,
                    isDirectory: false,
                    fileType: fileCategory
                )
                results.append(item)
            } catch {
                continue
            }
        }

        return results
    }
}
