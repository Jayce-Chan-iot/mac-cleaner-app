import SwiftUI

/// 重复文件检测视图 —— 按组展示 + 保留最旧策略
struct DuplicateFinderView: View {
    @EnvironmentObject var appState: AppState

    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var selectedFiles: Set<UUID> = []
    @State private var isLoading = false
    @State private var progressStage = ""
    @State private var progressValue: Double = 0
    @State private var showDeleteConfirmation = false
    @State private var showTrashResult = false
    @State private var trashResultMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            ModuleHeader(
                title: "重复文件检测",
                icon: "doc.on.doc.fill",
                action: { Task { await findDuplicates() } },
                actionLabel: "查找重复文件"
            )

            if isLoading {
                Spacer()
                ScanProgressOverlay(progress: progressValue, statusText: progressStage)
                Spacer()
            } else if duplicateGroups.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("点击「查找重复文件」扫描重复文件")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else {
                // 统计摘要
                summaryBar

                // 重复组列表
                groupList
            }

            // 底部操作栏
            if !duplicateGroups.isEmpty {
                bottomBar
            }
        }
        .padding(24)
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task { await executeDelete() }
            }
        } message: {
            let count = duplicateGroups
                .flatMap { $0.files }
                .filter { selectedFiles.contains($0.id) }
                .count
            Text("确定要删除选中的 \(count) 个重复文件吗？文件将移至回收站，保留 7 天后自动转至系统废纸篓。")
        }
        .alert("操作完成", isPresented: $showTrashResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(trashResultMessage)
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        let totalWaste = duplicateGroups.reduce(0 as Int64) { $0 + $1.wasteSize }
        let totalDuplicates = duplicateGroups.reduce(0) { $0 + $1.files.count - 1 }

        return HStack(spacing: 24) {
            StatCard(
                title: "重复组",
                value: "\(duplicateGroups.count) 组",
                icon: "rectangle.3.group",
                color: AppTheme.info
            )
            StatCard(
                title: "可删除文件",
                value: "\(totalDuplicates) 个",
                icon: "doc.badge.plus",
                color: AppTheme.warning
            )
            StatCard(
                title: "可释放空间",
                value: ByteCountFormatter.string(fromByteCount: totalWaste, countStyle: .file),
                icon: "arrow.up.bin",
                color: AppTheme.danger
            )
        }
    }

    // MARK: - Group List

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(duplicateGroups) { group in
                    duplicateGroupCard(group)
                }
            }
        }
    }

    // MARK: - Group Card

    private func duplicateGroupCard(_ group: DuplicateGroup) -> some View {
        VStack(spacing: 0) {
            // 组头部
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(AppTheme.info)

                VStack(alignment: .leading, spacing: 2) {
                    Text("重复组 \(String(group.fileHash.prefix(8)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(group.files.count) 个文件 × \(ByteCountFormatter.string(fromByteCount: group.fileSize, countStyle: .file))，可释放 \(group.formattedWasteSize)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Text(group.formattedWasteSize)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.danger)
            }
            .padding(12)

            Divider().background(AppTheme.border.opacity(0.3))

            // 文件列表（除第一个外默认勾选）
            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                let isOriginal = index == 0
                let isSelected = selectedFiles.contains(file.id)

                HStack(spacing: 10) {
                    if !isOriginal {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                            .font(.system(size: 14))
                            .onTapGesture {
                                if isSelected {
                                    selectedFiles.remove(file.id)
                                } else {
                                    selectedFiles.insert(file.id)
                                }
                            }
                    } else {
                        Image(systemName: "star.fill")
                            .foregroundColor(AppTheme.warning)
                            .font(.system(size: 14))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text(file.url.deletingLastPathComponent().path)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isOriginal {
                        Text("保留")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.warning.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if index < group.files.count - 1 {
                    Divider()
                        .background(AppTheme.border.opacity(0.2))
                        .padding(.leading, 40)
                }
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let selectedSize = duplicateGroups
            .flatMap { $0.files }
            .filter { selectedFiles.contains($0.id) }
            .reduce(0 as Int64) { $0 + $1.size }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(selectedFiles.count) 个重复文件")
                    .font(.system(size: 13))
                Text("删除可释放 \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
            }

            Spacer()

            Button("全部选中") {
                for group in duplicateGroups {
                    for (index, file) in group.files.enumerated() where index > 0 {
                        selectedFiles.insert(file.id)
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.textSecondary)
            .font(.system(size: 12))

            Button {
                deleteSelected()
            } label: {
                Label("删除选中", systemImage: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.danger)
            .disabled(selectedFiles.isEmpty)
        }
        .padding(12)
        .cardStyle()
    }

    // MARK: - Actions

    private func findDuplicates() async {
        isLoading = true
        progressValue = 0

        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let detector = DuplicateDetector()
            duplicateGroups = try await detector.findDuplicates(in: home) { stage, progress in
                Task { @MainActor in
                    progressStage = stage
                    progressValue = progress
                }
            }

            // 默认勾选重复项（每组从第 2 个起）
            selectedFiles.removeAll()
            for group in duplicateGroups {
                for (index, file) in group.files.enumerated() where index > 0 {
                    selectedFiles.insert(file.id)
                }
            }
        } catch {
            duplicateGroups = []
        }

        isLoading = false
    }

    private func deleteSelected() {
        let count = duplicateGroups
            .flatMap { $0.files }
            .filter { selectedFiles.contains($0.id) }
            .count
        guard count > 0 else { return }
        showDeleteConfirmation = true
    }

    private func executeDelete() async {
        let urls = duplicateGroups
            .flatMap { $0.files }
            .filter { selectedFiles.contains($0.id) }
            .map { $0.url }

        let items = (try? await appState.trashManager.moveToTrash(urls)) ?? []
        appState.totalCleanedSize += items.reduce(0 as Int64) { $0 + $1.size }

        for i in duplicateGroups.indices.reversed() {
            guard i < duplicateGroups.count else { continue }
            duplicateGroups[i].files.removeAll { selectedFiles.contains($0.id) }
            if duplicateGroups[i].files.count <= 1 {
                duplicateGroups.remove(at: i)
            }
        }
        selectedFiles.removeAll()

        trashResultMessage = "✅ \(items.count) 个文件已移入回收站，保留 7 天。"
        showTrashResult = true
    }
}
