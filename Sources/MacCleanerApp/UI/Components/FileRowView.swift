import SwiftUI

/// 文件行视图 —— 在列表中展示单个文件信息
struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false
    var showCheckbox: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showCheckbox {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                    .font(.system(size: 16))
            }

            // 文件图标
            Image(systemName: file.fileType.iconName)
                .font(.system(size: 20))
                .foregroundColor(ColorPalette.color(for: file.fileType))
                .frame(width: 28, height: 28)

            // 文件信息
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)

                    if file.modificationDate != nil {
                        Text("·")
                            .foregroundColor(AppTheme.textSecondary)
                        Text(file.relativeModificationDate)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }

            Spacer()

            // 文件大小
            SizeBadge(size: file.size)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 大小标签

struct SizeBadge: View {
    let size: Int64

    var body: some View {
        Text(formattedSize)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(ColorPalette.color(forFileSize: size))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorPalette.color(forFileSize: size).opacity(0.15))
            )
    }

    private var formattedSize: String {
        if size >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(size) / 1_000_000_000)
        } else if size >= 1_000_000 {
            return String(format: "%.1f MB", Double(size) / 1_000_000)
        } else if size >= 1_000 {
            return String(format: "%.0f KB", Double(size) / 1_000)
        } else {
            return "\(size) B"
        }
    }
}

// MARK: - 统计卡片

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardStyle()
    }
}
