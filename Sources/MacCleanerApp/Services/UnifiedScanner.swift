import Foundation
import CryptoKit

/// 统一扫描引擎 — 一次流式遍历 Home 目录，同时完成垃圾识别、大文件筛选、重复文件收集
/// 替代 FileScanner + JunkDetector + DuplicateDetector 的三轮全量扫描
actor UnifiedScanner {
    private let fileManager = FileManager.default
    private let junkDetector = JunkDetector()

    /// 每个类别最多保留的文件数（内存控制）
    private let maxPerCategory = 500

    /// 扫描中间产出
    private struct ScanState {
        var junkFiles: [JunkCategory: [FileItem]] = [:]
        var largeFiles: [FileItem] = []
        var duplicateCandidates: [Int64: [FileItem]] = [:] // 按大小分桶
        var categorizedFiles: [FileItem.FileCategory: [FileItem]] = [:]
        var scannedCount: Int = 0
    }

    // MARK: - Public API

    /// 执行统一扫描
    /// - Returns: (垃圾文件, 大文件列表, 重复文件组)
    func scan(
        rootURL: URL,
        minLargeFileSize: Int64 = 100_000_000,
        olderThanDays: Int = 180,
        progressHandler: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> (
        junk: [JunkCategory: [FileItem]],
        largeFiles: [FileItem],
        duplicates: [DuplicateGroup],
        categorized: [FileItem.FileCategory: [FileItem]]
    ) {
        var state = ScanState()

        // Step A: 流式遍历 + 三路分流
        progressHandler?("扫描文件系统...", 0.05)
        try streamScan(rootURL: rootURL, state: &state) { count in
            progressHandler?("已扫描 \(count) 个文件...", 0.05 + 0.3 * min(1.0, Double(count) / 50000.0))
        }

        // Step B: 大文件筛选排序
        progressHandler?("筛选大文件...", 0.40)
        let largeFiles = state.largeFiles
            .filter { $0.size >= minLargeFileSize || $0.isOldFile(olderThan: olderThanDays) }
            .sorted { $0.size > $1.size }

        // Step C: 重复检测（SHA-256 验证）
        progressHandler?("检测重复文件...", 0.50)
        let duplicateGroups = try await verifyDuplicates(
            sizeBuckets: state.duplicateCandidates.filter { $0.value.count >= 2 },
            progressHandler: { progress in
                progressHandler?("重复检测: \(Int(progress * 100))%", 0.50 + progress * 0.45)
            }
        )

        progressHandler?("扫描完成", 1.0)
        return (
            junk: state.junkFiles,
            largeFiles: largeFiles,
            duplicates: duplicateGroups,
            categorized: state.categorizedFiles
        )
    }

    // MARK: - Streaming scan

    private func streamScan(
        rootURL: URL,
        state: inout ScanState,
        progressHandler: ((Int) -> Void)? = nil
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
                .contentAccessDateKey, .creationDateKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in return true }
        ) else { return }

        var batch: [(URL, Int64, Date?, Date?, Date?, String)] = []
        let batchSize = 500

        for case let fileURL as URL in enumerator {
            // 跳过受保护路径
            guard !fileURL.path.hasPrefix("/System"),
                  !fileURL.path.hasPrefix("/private/var") else { continue }

            state.scannedCount += 1

            autoreleasepool {
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
                    .contentAccessDateKey, .creationDateKey
                ]) else { return }

                guard values.isDirectory != true else { return }
                let size = Int64(values.fileSize ?? 0)
                guard size > 0 else { return }

                let modDate = values.contentModificationDate
                let accessDate = values.contentAccessDate
                let createDate = values.creationDate
                let ext = fileURL.pathExtension

                batch.append((fileURL, size, modDate, accessDate, createDate, ext))

                if batch.count >= batchSize {
                    let flushed = batch
                    batch.removeAll(keepingCapacity: true)
                    processBatch(flushed, state: &state)
                }
            }
        }

        // 处理最后一批
        if !batch.isEmpty {
            processBatch(batch, state: &state)
        }

        // 释放批次内最后一个引用
        batch.removeAll()

        progressHandler?(state.scannedCount)
    }

    private func processBatch(
        _ batch: [(URL, Int64, Date?, Date?, Date?, String)],
        state: inout ScanState
    ) {
        for (fileURL, size, modDate, accessDate, createDate, ext) in batch {
            let fileType = FileItem.FileCategory.from(extension: ext)
            let item = FileItem(
                url: fileURL,
                fileName: fileURL.lastPathComponent,
                fileExtension: ext,
                size: size,
                modificationDate: modDate,
                lastAccessDate: accessDate,
                creationDate: createDate,
                isDirectory: false,
                fileType: fileType
            )

            // 1. 垃圾规则匹配 — 每个类别只保留 top-N by size
            for (category, baseURL, pattern) in junkDetector.rules {
                if junkDetector.matchesRule(url: fileURL, baseURL: baseURL, pattern: pattern) {
                    var arr = state.junkFiles[category, default: []]
                    arr.append(item)
                    let excess = arr.count - maxPerCategory
                    if excess > 0 {
                        arr.sort { $0.size > $1.size }
                        arr.removeLast(excess)
                    }
                    state.junkFiles[category] = arr
                    break
                }
            }

            // 2. 大文件收集 — 堆维护 top-1000
            if size >= 50_000_000 {
                state.largeFiles.append(item)
                let excessLarge = state.largeFiles.count - 1000
                if excessLarge > 0 {
                    state.largeFiles.sort { $0.size > $1.size }
                    state.largeFiles.removeLast(excessLarge)
                }
            }

            // 3. 重复文件按大小分桶（每组最多 200 个，超量删除最小的）
            if size >= 1024 {
                var bucket = state.duplicateCandidates[size, default: []]
                if bucket.count < 200 {
                    bucket.append(item)
                }
                state.duplicateCandidates[size] = bucket
            }

            // 4. 按文件类型分类 — 每个类型只保留 top-N by size
            var catArr = state.categorizedFiles[fileType, default: []]
            catArr.append(item)
            let catExcess = catArr.count - maxPerCategory
            if catExcess > 0 {
                catArr.sort { $0.size > $1.size }
                catArr.removeLast(catExcess)
            }
            state.categorizedFiles[fileType] = catArr
        }
    }

    // MARK: - Duplicate verification (Czkawka algorithm)

    private func verifyDuplicates(
        sizeBuckets: [Int64: [FileItem]],
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> [DuplicateGroup] {
        var allGroups: [DuplicateGroup] = []
        var processedCount = 0
        let totalCount = sizeBuckets.count
        guard totalCount > 0 else { return [] }

        for (size, files) in sizeBuckets {
            defer {
                processedCount += 1
                progressHandler?(Double(processedCount) / Double(totalCount))
            }

            // Phase 1: 前 4KB 哈希分组
            var prefixGroups: [String: [FileItem]] = [:]
            for file in files {
                guard let handle = try? FileHandle(forReadingFrom: file.url) else { continue }
                let data = (try? handle.read(upToCount: 4096)) ?? Data()
                try? handle.close()
                if data.isEmpty { continue }
                let hash = SHA256.hash(data: data)
                let key = hash.compactMap { String(format: "%02x", $0) }.joined()
                prefixGroups[key, default: []].append(file)
            }

            // Phase 2: 完整哈希确认（跳过 >500MB 文件，用前缀哈希代替）
            for (prefixKey, samePrefix) in prefixGroups where samePrefix.count >= 2 {
                var fullGroups: [String: [FileItem]] = [:]
                for file in samePrefix {
                    let hashKey: String
                    if file.size > 500_000_000 {
                        hashKey = prefixKey  // 大文件用前缀哈希代替
                    } else {
                        guard let data = try? Data(contentsOf: file.url, options: [.mappedIfSafe]) else { continue }
                        let hash = SHA256.hash(data: data)
                        hashKey = hash.compactMap { String(format: "%02x", $0) }.joined()
                    }
                    fullGroups[hashKey, default: []].append(file)
                }
                for (hash, dups) in fullGroups where dups.count >= 2 {
                    allGroups.append(DuplicateGroup(
                        fileSize: size,
                        fileHash: String(hash.prefix(12)),
                        files: dups.sorted { $0.size > $1.size }
                    ))
                }
            }
        }

        // 按可释放空间降序
        return allGroups.sorted { $0.wasteSize > $1.wasteSize }
    }
}
