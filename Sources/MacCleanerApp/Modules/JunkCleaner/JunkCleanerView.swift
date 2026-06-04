import SwiftUI

/// 垃圾清理视图 —— 三级安全体系 + 折叠面板 + 预览删除
struct JunkCleanerView: View {
    @EnvironmentObject var appState: AppState

    @State private var junkResults: [JunkCategory: [FileItem]] = [:]
    @State private var selectedFiles: Set<UUID> = []
    @State private var expandedSections: Set<JunkCategory.SafetyLevel> = [.safe]
    @State private var isLoading = false
    @State private var showPreview = false
    @State private var showLog = false
    @State private var operationLogEntries: [SafetyLogEntry] = []
    @State private var showFileDetail = false
    @State private var detailCategoryName: String = ""
    @State private var detailFiles: [FileItem] = []
    @State private var showDeleteConfirmation = false
    @State private var showTrashResult = false
    @State private var trashResultMessage = ""
    @State private var pendingDeleteURLs: [URL] = []

    private var selectedTotalSize: Int64 {
        var total: Int64 = 0
        for (_, files) in junkResults {
            for file in files where selectedFiles.contains(file.id) {
                total += file.size
            }
        }
        return total
    }

    var body: some View {
        VStack(spacing: 16) {
            ModuleHeader(
                title: "垃圾清理",
                icon: "trash.fill",
                action: { Task { await scanJunk() } },
                actionLabel: "扫描垃圾"
            )

            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(appState.scanStatusText)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else if junkResults.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("点击「扫描垃圾」分析可清理的系统垃圾")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else {
                // 三级面板
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(JunkCategory.SafetyLevel.allCases) { level in
                            safetySection(level)
                        }
                    }
                }

                // 底部操作栏
                bottomBar
            }
        }
        .padding(24)
        .sheet(isPresented: $showPreview) {
            previewSheet
        }
        .sheet(isPresented: $showLog) {
            operationLogSheet
        }
        .sheet(isPresented: $showFileDetail) {
            fileDetailSheet
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task { await executeCleanup() }
            }
        } message: {
            Text("确定要删除选中的 \(pendingDeleteURLs.count) 个文件吗？文件将移至回收站，保留 7 天后自动转至系统废纸篓。")
        }
        .alert("清理完成", isPresented: $showTrashResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(trashResultMessage)
        }
    }

    // MARK: - File Detail Sheet

    private var fileDetailSheet: some View {
        VStack(spacing: 0) {
            Text(detailCategoryName)
                .font(.system(size: 16, weight: .semibold))
                .padding()

            Divider()

            if detailFiles.isEmpty {
                Spacer()
                Text("暂无文件")
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
            } else {
                List {
                    ForEach(detailFiles.prefix(500)) { file in
                        FileRowView(file: file, isSelected: false)
                            .contextMenu {
                                Button("在访达中显示") {
                                    NSWorkspace.shared.selectFile(
                                        file.url.path,
                                        inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path
                                    )
                                }
                            }
                    }
                    if detailFiles.count > 500 {
                        Text("... 还有 \(detailFiles.count - 500) 个文件未显示")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 650, height: 500)
    }

    // MARK: - Safety Section

    private func safetySection(_ level: JunkCategory.SafetyLevel) -> some View {
        let categories = JunkCategory.allCases.filter { $0.safetyLevel == level }
        let isExpanded = expandedSections.contains(level)

        return VStack(spacing: 0) {
            // Section Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSections.remove(level)
                    } else {
                        expandedSections.insert(level)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))

                    Circle()
                        .fill(ColorPalette.color(for: level))
                        .frame(width: 8, height: 8)

                    Text(level.rawValue)
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    let sectionSize = categories.reduce(0 as Int64) { total, cat in
                        total + (junkResults[cat] ?? []).reduce(0) { $0 + $1.size }
                    }
                    Text(ByteCountFormatter.string(fromByteCount: sectionSize, countStyle: .file))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceHighlight.opacity(0.5))
                .foregroundColor(AppTheme.textPrimary)
            }
            .buttonStyle(.plain)

            // Expanded categories
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(categories) { category in
                        categoryRow(category)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider()
                .background(AppTheme.border.opacity(0.3))
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Category Row

    private func categoryRow(_ category: JunkCategory) -> some View {
        let files = junkResults[category] ?? []
        let categorySize = files.reduce(0 as Int64) { $0 + $1.size }
        let allSelected = !files.isEmpty && files.allSatisfy { selectedFiles.contains($0.id) }
        let someSelected = files.contains { selectedFiles.contains($0.id) }

        return VStack(spacing: 4) {
            // Category header — select on tap, detail on info button
            HStack(spacing: 0) {
                Button {
                    if allSelected {
                        for f in files { selectedFiles.remove(f.id) }
                    } else {
                        for f in files { selectedFiles.insert(f.id) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: allSelected ? "checkmark.circle.fill" :
                                someSelected ? "minus.circle.fill" : "circle")
                            .foregroundColor(allSelected ? AppTheme.accent :
                                someSelected ? AppTheme.warning : AppTheme.textSecondary)
                            .font(.system(size: 14))

                        Image(systemName: category.iconName)
                            .font(.system(size: 14))
                            .foregroundColor(ColorPalette.color(for: category.safetyLevel))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(category.description)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(ByteCountFormatter.string(fromByteCount: categorySize, countStyle: .file))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(files.count) 个文件")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                // 详情按钮
                Button {
                    detailCategoryName = category.displayName
                    let captured = files
                    Task.detached(priority: .background) {
                        let sorted = captured.sorted { $0.size > $1.size }
                        await MainActor.run {
                            detailFiles = sorted
                            showFileDetail = true
                        }
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accent.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .opacity(files.isEmpty ? 0.3 : 1.0)
                .disabled(files.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // 汇总信息
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(selectedFiles.count) 个文件")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textPrimary)
                Text("可释放 \(ByteCountFormatter.string(fromByteCount: selectedTotalSize, countStyle: .file))")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 8) {
                Button("预览") {
                    showPreview = true
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.textSecondary)

                Button {
                    performCleanup()
                } label: {
                    Label("清理选中项", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.danger)
                .disabled(selectedFiles.isEmpty)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func scanJunk() async {
        isLoading = true
        junkResults = [:]

        do {
            let detector = JunkDetector()
            junkResults = try await detector.scanJunk { current, total, category in
                Task { @MainActor in
                    appState.scanStatusText = "\(category) (\(current)/\(total))"
                }
            }
            // 默认全选安全级别的所有文件
            for (category, files) in junkResults where category.safetyLevel == .safe {
                for file in files { selectedFiles.insert(file.id) }
            }
        } catch {
            appState.scanStatusText = "扫描失败"
        }

        isLoading = false
    }

    private func performCleanup() {
        let urls = junkResults.values
            .flatMap { $0 }
            .filter { selectedFiles.contains($0.id) }
            .map { $0.url }
        guard !urls.isEmpty else { return }
        pendingDeleteURLs = urls
        showDeleteConfirmation = true
    }

    private func executeCleanup() async {
        do {
            let items = try await appState.trashManager.moveToTrash(pendingDeleteURLs)
            appState.totalCleanedSize += items.reduce(0 as Int64) { $0 + $1.size }
            trashResultMessage = "✅ 已移入「回收站」\(items.count) 个文件，保留 7 天后自动转至系统废纸篓。可在回收站页面恢复或彻底删除。"

            let freed = ByteCountFormatter.string(
                fromByteCount: items.reduce(0 as Int64) { $0 + $1.size },
                countStyle: .file
            )
            DynamicIslandController.shared.showCleanComplete(freedSize: freed)

            selectedFiles.removeAll()
            junkResults = [:]
            await scanJunk()
        } catch {
            trashResultMessage = "操作失败: \(error.localizedDescription)"
        }
        showTrashResult = true
    }

    // MARK: - Preview Sheet

    private var previewSheet: some View {
        VStack(spacing: 0) {
            Text("清理预览")
                .font(.system(size: 16, weight: .semibold))
                .padding()

            Divider()

            List {
                ForEach(
                    junkResults.values
                        .flatMap { $0 }
                        .filter { selectedFiles.contains($0.id) }
                        .sorted { $0.size > $1.size }
                ) { file in
                    FileRowView(file: file, isSelected: true)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Operation Log Sheet

    private var operationLogSheet: some View {
        VStack(spacing: 0) {
            Text("操作日志")
                .font(.system(size: 16, weight: .semibold))
                .padding()

            Divider()

            List {
                ForEach(operationLogEntries) { entry in
                    HStack {
                        Circle()
                            .fill(entry.action == .deleted ? AppTheme.safe :
                                    entry.action == .skipped ? AppTheme.warning : AppTheme.danger)
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.url.lastPathComponent)
                                .font(.system(size: 12))
                            Text(entry.detail ?? "")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                        Text(entry.action.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 500, height: 400)
        .task {
            operationLogEntries = await appState.safetyManager.getLog()
        }
    }
}
