import SwiftUI

/// 回收站页面 — 展示已删除文件，支持恢复和彻底删除
struct TrashBinView: View {
    @EnvironmentObject var appState: AppState

    @State private var items: [TrashItem] = []
    @State private var selectedItems: Set<String> = []
    @State private var showPermanentDeleteAlert = false
    @State private var resultMessage: String?
    @State private var showResult = false

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("回收站")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("文件删除后在此保留 7 天，过期自动转至系统废纸篓")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    Task { await loadItems() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.textSecondary)
            }

            // 统计栏
            if !items.isEmpty {
                HStack(spacing: 16) {
                    StatCard(
                        title: "文件数",
                        value: "\(items.count) 个",
                        icon: "doc",
                        color: AppTheme.info
                    )
                    StatCard(
                        title: "总大小",
                        value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                        icon: "internaldrive",
                        color: AppTheme.accent
                    )
                }
            }

            // 内容
            if items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("回收站为空")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("删除的文件会出现在这里，保留 7 天后自动清理")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary.opacity(0.7))
                }
                Spacer()
            } else {
                itemList

                // 批量操作栏
                if !selectedItems.isEmpty {
                    bulkActionBar
                }
            }
        }
        .padding(24)
        .task {
            await loadItems()
        }
        .alert("彻底删除", isPresented: $showPermanentDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("彻底删除", role: .destructive) {
                Task { await performPermanentDelete() }
            }
        } message: {
            Text("确定要彻底删除选中的 \(selectedItems.count) 个文件吗？文件将移入系统废纸篓。")
        }
        .alert("操作结果", isPresented: $showResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(items, id: \.id) { item in
                    trashItemRow(item)
                }
            }
        }
    }

    private var bulkActionBar: some View {
        HStack {
            Text("已选 \(selectedItems.count) 个文件")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            Button {
                Task { await restoreSelected() }
            } label: {
                Label("恢复选中 (\(selectedItems.count))", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)

            Button {
                showPermanentDeleteAlert = true
            } label: {
                Label("彻底删除选中 (\(selectedItems.count))", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.danger)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func trashItemRow(_ item: TrashItem) -> some View {
        let isSelected = selectedItems.contains(item.id)

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                .font(.system(size: 14))
                .onTapGesture {
                    if isSelected {
                        selectedItems.remove(item.id)
                    } else {
                        selectedItems.insert(item.id)
                    }
                }

            Image(systemName: iconForExtension(item.fileName))
                .font(.system(size: 20))
                .foregroundColor(AppTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(item.originalPath)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(item.remainingDays) 天后过期")
                    .font(.system(size: 10))
                    .foregroundColor(item.remainingDays <= 1 ? AppTheme.danger : AppTheme.warning)
                Text(item.formattedExpiresAt)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .frame(width: 80)

            HStack(spacing: 6) {
                Button {
                    Task { await restoreItem(item) }
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func loadItems() async {
        items = await appState.trashManager.getItems()
    }

    private func restoreItem(_ item: TrashItem) async {
        do {
            try await appState.trashManager.restore(item)
            resultMessage = "「\(item.fileName)」已恢复到原位置"
            showResult = true
            await loadItems()
        } catch {
            resultMessage = "恢复失败: \(error.localizedDescription)"
            showResult = true
        }
    }

    private func restoreSelected() async {
        let targets = items.filter { selectedItems.contains($0.id) }
        var successCount = 0
        for item in targets {
            do {
                try await appState.trashManager.restore(item)
                successCount += 1
            } catch {}
        }
        resultMessage = "已恢复 \(successCount)/\(targets.count) 个文件"
        showResult = true
        selectedItems.removeAll()
        await loadItems()
    }

    private func performPermanentDelete() async {
        let targets = items.filter { selectedItems.contains($0.id) }
        var successCount = 0
        for item in targets {
            do {
                try await appState.trashManager.permanentlyDelete(item)
                successCount += 1
            } catch {}
        }
        if successCount == targets.count {
            resultMessage = "已移入系统废纸篓，\(successCount) 个文件"
        } else {
            resultMessage = "成功 \(successCount)/\(targets.count) 个文件，部分操作失败"
        }
        showResult = true
        selectedItems.removeAll()
        await loadItems()
    }

    private func iconForExtension(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let category = FileItem.FileCategory.from(extension: ext)
        return category.iconName
    }
}
