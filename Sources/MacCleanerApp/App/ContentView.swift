import SwiftUI

/// 主布局 —— NavigationSplitView 三栏结构
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // 主内容区
            detailContent
                .navigationSplitViewColumnWidth(min: 600, ideal: 700)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App 标题
            VStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.accent)
                Text("Mac 清理助手")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("文件分类 · 垃圾清理 · 磁盘分析")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .background(AppTheme.border)

            // 导航列表
            List(selection: $appState.selectedModule) {
                Section("功能") {
                    ForEach(Module.allCases) { module in
                        if module != .fileClassifier || module != .fileClassifier {
                            Label(module.title, systemImage: module.iconName)
                                .tag(module)
                                .font(.system(size: 13))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            // 底部状态
            VStack(spacing: 8) {
                Divider().background(AppTheme.border)

                if let lastScan = appState.lastScanDate {
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("上次扫描: \(formattedDate(lastScan))")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.textSecondary)

                        HStack {
                            Image(systemName: "trash.slash")
                                .font(.system(size: 10))
                            Text("已清理: \(appState.formattedCleanedSize)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.accent)
                    }
                }

                Button("操作日志") {
                    appState.showOperationLog.toggle()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 12)
        }
        .background(AppTheme.surface)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            // 背景
            AppTheme.background.ignoresSafeArea()

            // 模块内容
            switch appState.selectedModule {
            case .dashboard:
                DashboardView()
            case .fileClassifier:
                FileClassifierView()
            case .junkCleaner:
                JunkCleanerView()
            case .largeFileFinder:
                LargeFileFinderView()
            case .duplicateFinder:
                DuplicateFinderView()
            case .diskAnalyzer:
                DiskAnalyzerView()
            case .trashBin:
                TrashBinView()
            case .processManager:
                ProcessManagerView()
            case .appUninstaller:
                AppUninstallerView()
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
#endif
