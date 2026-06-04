import SwiftUI

/// 磁盘可视化分析视图 —— 复用 Sunburst 组件
struct DiskAnalyzerView: View {
    @EnvironmentObject var appState: AppState

    @State private var categorizedFiles: [FileItem.FileCategory: [FileItem]] = [:]
    @State private var radialBarData: RadialBarData?
    @State private var treeMapData: TreeMapData?
    @State private var isLoading = false
    @State private var selectedViewMode: ViewMode = .radialBar

    var body: some View {
        VStack(spacing: 16) {
            ModuleHeader(
                title: "磁盘分析",
                icon: "chart.pie.fill",
                action: { Task { await analyze() } },
                actionLabel: "开始分析"
            )

            // 视图模式切换
            viewModePicker

            ScrollView(.vertical, showsIndicators: true) {
                if isLoading {
                    Spacer()
                    ProgressView("正在分析磁盘...")
                    Spacer()
                } else if let data = radialBarData {
                    // 磁盘概览
                    diskSummary(data)

                    // 可视化区域
                    Group {
                        switch selectedViewMode {
                        case .radialBar:
                            RadialBarChart(data: data)
                                .frame(height: 350)
                        case .barChart:
                            barChartView(data)
                        case .treeMap:
                            if let tm = treeMapData {
                                TreeMapChart(data: tm)
                                    .frame(height: 280)
                            }
                        }
                    }

                    // 详情列表
                    detailBreakdown
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.textSecondary)
                        Text("点击「开始分析」查看磁盘空间分布")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(24)
    }

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        Picker("视图", selection: $selectedViewMode) {
            ForEach(ViewMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 400)
    }

    // MARK: - Disk Summary

    private func diskSummary(_ data: RadialBarData) -> some View {
        HStack(spacing: 12) {
            StatCard(
                title: "总扫描大小",
                value: data.formattedTotalSize,
                icon: "internaldrive",
                color: AppTheme.accent
            )
            StatCard(
                title: "文件类型",
                value: "\(data.bars.count) 类",
                icon: "folder",
                color: AppTheme.info
            )
            StatCard(
                title: "最大类别",
                value: data.bars.max(by: { $0.totalSize < $1.totalSize })?.category.rawValue ?? "-",
                icon: "crown",
                color: AppTheme.warning
            )
        }
    }

    // MARK: - Bar Chart

    private func barChartView(_ data: RadialBarData) -> some View {
        VStack(spacing: 8) {
            ForEach(data.bars.sorted(by: { $0.totalSize > $1.totalSize })) { segment in
                HStack(spacing: 10) {
                    Image(systemName: segment.category.iconName)
                        .foregroundColor(ColorPalette.color(for: segment.category))
                        .frame(width: 20)

                    Text(segment.category.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.border)
                                .frame(height: 20)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [ColorPalette.color(for: segment.category), ColorPalette.color(for: segment.category).opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(geo.size.width * CGFloat(Double(segment.totalSize) / Double(data.totalSize)), 4),
                                    height: 20
                                )
                        }
                    }
                    .frame(height: 20)

                    Text(ByteCountFormatter.string(fromByteCount: segment.totalSize, countStyle: .file))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 60, alignment: .trailing)

                    Text(String(format: "%.1f%%", Double(segment.totalSize) / Double(data.totalSize) * 100))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 45, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Detail Breakdown

    private var detailBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("详细分布")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            ForEach(FileItem.FileCategory.allCases) { category in
                let files = categorizedFiles[category] ?? []
                let catSize = files.reduce(0 as Int64) { $0 + $1.size }

                if catSize > 0 {
                    HStack {
                        Circle()
                            .fill(ColorPalette.color(for: category))
                            .frame(width: 8, height: 8)
                        Text(category.rawValue)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("\(files.count) 个文件")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                        Text(ByteCountFormatter.string(fromByteCount: catSize, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(AppTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .cardStyle()
                }
            }
        }
    }

    // MARK: - Actions

    private func analyze() async {
        isLoading = true
        let scanner = UnifiedScanner()

        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let appState = self.appState
            let (_, _, _, categorized) = try await scanner.scan(
                rootURL: home,
                progressHandler: { status, progress in
                    Task { @MainActor in
                        appState.scanStatusText = status
                    }
                }
            )
            categorizedFiles = categorized
            radialBarData = RadialBarData.build(from: categorized)
            treeMapData = TreeMapData.build(from: categorized)
        } catch {
            appState.scanStatusText = "分析失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - View Mode

    private enum ViewMode: String, CaseIterable, Identifiable {
        case radialBar = "辐射图"
        case barChart = "柱状图"
        case treeMap = "树图"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .radialBar: return "circle.circle"
            case .barChart: return "chart.bar"
            case .treeMap: return "square.grid.3x3"
            }
        }
    }
}
