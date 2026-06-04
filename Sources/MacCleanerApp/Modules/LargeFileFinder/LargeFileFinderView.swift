import SwiftUI

/// 大文件 & 旧文件查找视图
struct LargeFileFinderView: View {
    @EnvironmentObject var appState: AppState

    @State private var largeFiles: [FileItem] = []
    @State private var minSizeFilter: Int64 = 100_000_000 // 100 MB
    @State private var daysFilter: Int = 180
    @State private var isLoading = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var sortOrder: SortOrder = .sizeDesc
    @State private var showDeleteConfirmation = false
    @State private var showTrashResult = false
    @State private var trashResultMessage = ""

    private var filteredFiles: [FileItem] {
        largeFiles.filter { file in
            file.size >= minSizeFilter && file.isOldFile(olderThan: daysFilter)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ModuleHeader(
                title: "大文件 & 旧文件",
                icon: "doc.fill.badge.ellipsis",
                action: { Task { await findFiles() } },
                actionLabel: "查找文件"
            )

            // 筛选器
            filterBar

            // 文件列表
            if isLoading {
                Spacer()
                ProgressView("正在扫描...")
                Spacer()
            } else if filteredFiles.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("没有找到符合条件的大文件或旧文件")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else {
                fileList
            }

            // 底部操作栏
            if !filteredFiles.isEmpty {
                bottomBar
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task { await executeDelete() }
            }
        } message: {
            let urls = filteredFiles
                .filter { selectedFiles.contains($0.id) }
                .map { $0.url }
            Text("确定要删除选中的 \(urls.count) 个文件吗？文件将移至回收站，保留 7 天后自动转至系统废纸篓。")
        }
        .alert("操作完成", isPresented: $showTrashResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(trashResultMessage)
        }
        .padding(24)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 16) {
            // 大小筛选
            HStack(spacing: 6) {
                Text("大于")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Picker("", selection: $minSizeFilter) {
                    Text("10 MB").tag(10_000_000 as Int64)
                    Text("50 MB").tag(50_000_000 as Int64)
                    Text("100 MB").tag(100_000_000 as Int64)
                    Text("500 MB").tag(500_000_000 as Int64)
                    Text("1 GB").tag(1_000_000_000 as Int64)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .cardStyle()

            // 时间筛选
            HStack(spacing: 6) {
                Text("未访问超过")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Picker("", selection: $daysFilter) {
                    Text("1 个月").tag(30)
                    Text("3 个月").tag(90)
                    Text("6 个月").tag(180)
                    Text("1 年").tag(365)
                    Text("2 年").tag(730)
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .cardStyle()

            Spacer()

            Text("\(filteredFiles.count) 个文件")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
        }
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredFiles) { file in
                    FileRowView(
                        file: file,
                        isSelected: selectedFiles.contains(file.id),
                        showCheckbox: true
                    )
                    .onTapGesture {
                        if selectedFiles.contains(file.id) {
                            selectedFiles.remove(file.id)
                        } else {
                            selectedFiles.insert(file.id)
                        }
                    }
                    .contextMenu {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
                        }
                        Button("快速查看") {
                            NSWorkspace.shared.open(file.url)
                        }
                    }
                    Divider()
                        .background(AppTheme.border.opacity(0.3))
                        .padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let totalSize = filteredFiles
            .filter { selectedFiles.contains($0.id) }
            .reduce(0 as Int64) { $0 + $1.size }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(selectedFiles.count) 个文件")
                    .font(.system(size: 13))
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
            }

            Spacer()

            Button {
                moveSelectedToTrash()
            } label: {
                Label("移到废纸篓", systemImage: "trash")
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

    private func findFiles() async {
        isLoading = true

        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            largeFiles = try await appState.fileScanner.findLargeAndOldFiles(in: home) { count in
                // 进度已在内部处理
            }
        } catch {
            largeFiles = []
        }

        isLoading = false
    }

    private func moveSelectedToTrash() {
        let urls = filteredFiles
            .filter { selectedFiles.contains($0.id) }
            .map { $0.url }
        guard !urls.isEmpty else { return }
        showDeleteConfirmation = true
    }

    private func executeDelete() async {
        let urls = filteredFiles
            .filter { selectedFiles.contains($0.id) }
            .map { $0.url }

        let items = (try? await appState.trashManager.moveToTrash(urls)) ?? []
        appState.totalCleanedSize += items.reduce(0 as Int64) { $0 + $1.size }

        trashResultMessage = "✅ \(items.count) 个文件已移入回收站，保留 7 天。"

        largeFiles.removeAll { selectedFiles.contains($0.id) }
        selectedFiles.removeAll()
        showTrashResult = true
    }

    // MARK: - Sort Order

    private enum SortOrder: String, CaseIterable {
        case sizeDesc = "大小降序"
        case sizeAsc = "大小升序"
        case dateDesc = "最近修改"
        case dateAsc = "最早修改"
    }
}
