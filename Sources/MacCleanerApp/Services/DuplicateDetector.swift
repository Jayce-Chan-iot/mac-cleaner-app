import Foundation
import CryptoKit

/// 重复文件检测引擎
/// 算法参考 Czkawka 的三级哈希过滤策略
/// 1. 按文件大小分组 → 过滤唯一大小的组
/// 2. 对同大小组计算 SHA-256 前 4KB 哈希
/// 3. 前 4KB 匹配的，计算完整哈希确认
actor DuplicateDetector {
    private let fileManager = FileManager.default

    /// 最小检测文件大小（跳过过小文件）
    private let minFileSize: Int64 = 1024 // 1 KB
    /// 前哈希读取字节数
    private let hashPrefixSize = 4096 // 4 KB

    // MARK: - Public API

    /// 扫描指定目录寻找重复文件
    /// - Parameters:
    ///   - rootURL: 扫描根目录
    ///   - progressHandler: 进度回调 (当前阶段名称, 进度 0.0-1.0)
    /// - Returns: 重复文件组列表
    func findDuplicates(
        in rootURL: URL,
        progressHandler: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> [DuplicateGroup] {
        // 第 0 步：收集所有文件
        progressHandler?("收集文件列表...", 0.05)
        let allFiles = try await collectFiles(from: rootURL)

        guard !allFiles.isEmpty else { return [] }

        // 第 1 步：按文件大小分组，过滤唯一大小
        progressHandler?("按大小分组...", 0.15)
        let sizeGroups = groupBySize(allFiles)
            .filter { $0.value.count >= 2 }

        guard !sizeGroups.isEmpty else { return [] }

        // 第 2 步：对每组计算前 4KB 哈希
        progressHandler?("计算前置哈希...", 0.3)
        let prefixHashGroups = try await computePrefixHashes(sizeGroups)
            .filter { $0.value.count >= 2 }

        guard !prefixHashGroups.isEmpty else { return [] }

        // 第 3 步：完整哈希验证
        progressHandler?("验证完整哈希...", 0.6)
        let fullHashGroups = try await computeFullHashes(prefixHashGroups)
            .filter { $0.value.count >= 2 }

        // 构建结果
        progressHandler?("生成报告...", 0.9)
        let groups = fullHashGroups.map { (hash, files) -> DuplicateGroup in
            let sortedFiles = files.sorted { $0.size > $1.size }
            return DuplicateGroup(
                fileSize: sortedFiles.first?.size ?? 0,
                fileHash: String(hash.prefix(12)),
                files: sortedFiles
            )
        }
        .sorted { $0.wasteSize > $1.wasteSize }

        progressHandler?("完成", 1.0)
        return groups
    }

    // MARK: - Private

    private func collectFiles(from rootURL: URL) async throws -> [FileItem] {
        var results: [FileItem] = []

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
                .contentAccessDateKey, .creationDateKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return results
        }

        // 收集所有 URL（NSEnumerator 不支持 async 迭代）
        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
            .filter { url in
                !url.path.hasPrefix("/System") && !url.path.hasPrefix("/private/var")
            }

        for fileURL in allURLs {
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isDirectoryKey,
                    .contentAccessDateKey, .creationDateKey
                ])

                guard values.isDirectory != true else { continue }

                let size = Int64(values.fileSize ?? 0)
                guard size >= minFileSize else { continue }

                let ext = fileURL.pathExtension
                let category = FileItem.FileCategory.from(extension: ext)
                let modDate = values.contentModificationDate
                let accessDate = values.contentAccessDate
                let createDate = values.creationDate

                let item = FileItem(
                    url: fileURL,
                    fileName: fileURL.lastPathComponent,
                    fileExtension: ext,
                    size: size,
                    modificationDate: modDate,
                    lastAccessDate: accessDate,
                    creationDate: createDate,
                    isDirectory: false,
                    fileType: category
                )
                results.append(item)
            } catch {
                continue
            }
        }

        return results
    }

    /// 按文件大小分组
    private func groupBySize(_ files: [FileItem]) -> [Int64: [FileItem]] {
        Dictionary(grouping: files) { $0.size }
    }

    /// 计算前 4KB 哈希
    private func computePrefixHashes(_ sizeGroups: [Int64: [FileItem]]) async throws -> [String: [FileItem]] {
        var hashGroups: [String: [FileItem]] = [:]

        for (_, files) in sizeGroups {
            for file in files {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: file.url)
                    defer { try? fileHandle.close() }

                    let data = try fileHandle.read(upToCount: hashPrefixSize) ?? Data()
                    let hash = SHA256.hash(data: data)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

                    hashGroups[hashString, default: []].append(file)
                } catch {
                    continue
                }
            }
        }

        return hashGroups
    }

    /// 完整文件哈希验证
    private func computeFullHashes(_ prefixHashGroups: [String: [FileItem]]) async throws -> [String: [FileItem]] {
        var fullHashGroups: [String: [FileItem]] = [:]

        for (_, files) in prefixHashGroups {
            var fileHashMap: [String: [FileItem]] = [:]

            for file in files {
                do {
                    let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
                    let hash = SHA256.hash(data: data)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

                    fileHashMap[hashString, default: []].append(file)
                } catch {
                    // 跳过超大或无法读取的文件
                    continue
                }
            }

            for (hash, duplicateFiles) in fileHashMap where duplicateFiles.count >= 2 {
                fullHashGroups[hash] = duplicateFiles
            }
        }

        return fullHashGroups
    }
}
