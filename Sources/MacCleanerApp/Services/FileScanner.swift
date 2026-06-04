import Foundation

/// 通用文件扫描引擎
/// 参考 Pearcleaner 的扫描架构，使用 GCD 并发遍历目录
actor FileScanner {
    private let fileManager = FileManager.default
    private let safetyManager = SafetyManager()
    private let scanQueue = DispatchQueue(
        label: "com.maccleaner.filescanner",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // MARK: - Public API

    /// 扫描指定目录，按文件类型分类
    func scanDirectory(
        _ rootURL: URL,
        maxDepth: Int = 10,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [FileItem.FileCategory: [FileItem]] {
        var categorized: [FileItem.FileCategory: [FileItem]] = [:]
        let allFiles = try await enumerateFiles(from: rootURL, maxDepth: maxDepth)

        for file in allFiles {
            categorized[file.fileType, default: []].append(file)
        }

        progressHandler?(allFiles.count, allFiles.count)
        return categorized
    }

    /// 查找大文件（默认 >100MB）和旧文件（默认 >180 天）
    func findLargeAndOldFiles(
        in rootURL: URL,
        minSize: Int64 = 100_000_000,
        olderThanDays: Int = 180,
        maxDepth: Int = 10,
        progressHandler: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [FileItem] {
        let allFiles = try await enumerateFiles(from: rootURL, maxDepth: maxDepth)
        var results: [FileItem] = []

        for file in allFiles {
            if file.size >= minSize || file.isOldFile(olderThan: olderThanDays) {
                results.append(file)
            }
            progressHandler?(results.count)
        }

        // 按大小降序排列
        results.sort { $0.size > $1.size }
        return results
    }

    /// 获取磁盘信息
    func getDiskInfo(for url: URL) throws -> DiskInfo {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey
        ])

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacity ?? 0)

        return DiskInfo(
            totalCapacity: total,
            availableCapacity: available,
            usedCapacity: total - available,
            volumeName: values.volumeName ?? "Unknown"
        )
    }

    // MARK: - Private

    /// 递归遍历文件系统，使用并发 + 防递归死循环
    private func enumerateFiles(from rootURL: URL, maxDepth: Int) async throws -> [FileItem] {
        var results: [FileItem] = []
        var urlsToProcess: [(URL, Int)] = [(rootURL, 0)]

        while !urlsToProcess.isEmpty {
            let batch = urlsToProcess.prefix(50)
            urlsToProcess.removeFirst(min(50, urlsToProcess.count))

            // 并发处理一批目录
            let batchResults: [[FileItem]] = try await withThrowingTaskGroup(of: (URL, Int, [FileItem], [(URL, Int)]).self) { group in
                for (url, depth) in batch {
                    group.addTask {
                        return await self.processDirectory(at: url, depth: depth, maxDepth: maxDepth)
                    }
                }

                var items: [[FileItem]] = []
                for try await (_, _, files, nextDirs) in group {
                    items.append(files)
                    urlsToProcess.append(contentsOf: nextDirs)
                }
                return items
            }

            for itemBatch in batchResults {
                results.append(contentsOf: itemBatch)
            }
        }

        return results
    }

    /// 处理单个目录
    private func processDirectory(
        at url: URL,
        depth: Int,
        maxDepth: Int
    ) -> (URL, Int, [FileItem], [(URL, Int)]) {
        var files: [FileItem] = []
        var subdirs: [(URL, Int)] = []

        guard depth < maxDepth,
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .totalFileAllocatedSizeKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
              )
        else {
            return (url, depth, files, subdirs)
        }

        for case let fileURL as URL in enumerator {
            // 跳过受保护路径
            guard !url.path.hasPrefix("/System"),
                  !url.path.hasPrefix("/private/var") else {
                continue
            }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .contentAccessDateKey,
                    .creationDateKey
                ])

                let isDir = resourceValues.isDirectory ?? false
                let size = Int64(resourceValues.fileSize ?? 0)
                let modDate = resourceValues.contentModificationDate
                let accessDate = resourceValues.contentAccessDate
                let createDate = resourceValues.creationDate

                if isDir {
                    // 检查深度限制
                    let currentDepth = fileURL.path.components(separatedBy: "/").count
                        - url.path.components(separatedBy: "/").count
                    if currentDepth < maxDepth {
                        subdirs.append((fileURL, depth + 1))
                    }
                } else {
                    let ext = fileURL.pathExtension
                    let category = FileItem.FileCategory.from(extension: ext)

                    let item = FileItem(
                        url: fileURL,
                        fileName: fileURL.lastPathComponent,
                        fileExtension: ext,
                        size: size > 0 ? size : 0,
                        modificationDate: modDate,
                        lastAccessDate: accessDate,
                        creationDate: createDate,
                        isDirectory: false,
                        fileType: category
                    )
                    files.append(item)

                    // 每 100 个文件暂停一下给系统让路
                    if files.count % 100 == 0 {
                        enumerator.skipDescendants()
                    }
                }
            } catch {
                // 跳过无法读取的文件
                continue
            }
        }

        return (url, depth, files, subdirs)
    }
}
