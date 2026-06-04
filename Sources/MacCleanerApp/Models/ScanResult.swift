import Foundation

/// 扫描结果，聚合一次完整扫描的全部信息
struct ScanResult: Identifiable {
    let id = UUID()
    let scanDate: Date
    let scanDuration: TimeInterval
    let totalScannedFiles: Int
    let totalScannedSize: Int64

    /// 分类扫描文件
    var categorizedFiles: [FileItem.FileCategory: [FileItem]]
    /// 垃圾文件按类别分组
    var junkFiles: [JunkCategory: [FileItem]]
    /// 大文件列表（>100MB）
    var largeFiles: [FileItem]
    /// 重复文件组
    var duplicateGroups: [DuplicateGroup]
    /// 磁盘信息
    var diskInfo: DiskInfo

    var formattedScanDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: scanDate)
    }

    var formattedDuration: String {
        String(format: "%.1f 秒", scanDuration)
    }

    var totalJunkSize: Int64 {
        junkFiles.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    var formattedJunkSize: String {
        ByteCountFormatter.string(fromByteCount: totalJunkSize, countStyle: .file)
    }
}

/// 重复文件组
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let fileSize: Int64
    let fileHash: String  // SHA-256 前 12 位
    var files: [FileItem]

    var wasteSize: Int64 {
        fileSize * Int64(files.count - 1)
    }

    var formattedWasteSize: String {
        ByteCountFormatter.string(fromByteCount: wasteSize, countStyle: .file)
    }
}

/// 磁盘信息
struct DiskInfo {
    let totalCapacity: Int64
    let availableCapacity: Int64
    let usedCapacity: Int64
    let volumeName: String

    var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }
}
