import SwiftUI

/// 仪表盘视图 —— 磁盘概览 + 一键扫描
struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ModuleHeader(title: "仪表盘", icon: "gauge.with.dots.needle.33percent")

                // 磁盘概览卡片
                if let result = appState.lastScanResult {
                    diskOverview(result.diskInfo)
                } else {
                    diskPlaceholder
                }

                // 一键扫描按钮
                scanButton

                // 统计卡片行
                if let result = appState.lastScanResult {
                    statsRow(result)
                }

                // 最近扫描信息
                if let result = appState.lastScanResult {
                    recentScanInfo(result)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Disk Overview

    private func diskOverview(_ info: DiskInfo) -> some View {
        HStack(spacing: 24) {
            // 环形图
            ZStack {
                Circle()
                    .stroke(AppTheme.border, lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: info.usagePercentage)
                    .stroke(
                        AngularGradient(
                            colors: [
                                ColorPalette.sizeGradient[0],
                                ColorPalette.sizeGradient[2],
                                ColorPalette.sizeGradient[4]
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", info.usagePercentage * 100))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("已用")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            // 磁盘详情
            VStack(alignment: .leading, spacing: 12) {
                Text(info.volumeName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "总容量", value: info.formattedTotal)
                    DetailRow(label: "可用", value: info.formattedAvailable, color: AppTheme.safe)
                    DetailRow(label: "已用", value: info.formattedUsed, color: AppTheme.warning)
                }
            }

            Spacer()
        }
        .padding(20)
        .gradientBorderCard()
    }

    private var diskPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.textSecondary)
                Text("点击下方按钮开始首次扫描")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(40)
            Spacer()
        }
        .cardStyle()
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            appState.startScan()
        } label: {
            HStack(spacing: 12) {
                if appState.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                }
                Text(appState.isScanning ? "扫描中..." : "一键扫描")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, Color(hex: "00A8FF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(appState.isScanning ? 0.5 : 1.0)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(appState.isScanning)
    }

    // MARK: - Stats Row

    private func statsRow(_ result: ScanResult) -> some View {
        HStack(spacing: 12) {
            StatCard(
                title: "垃圾文件",
                value: result.formattedJunkSize,
                icon: "trash.fill",
                color: AppTheme.danger
            )
            StatCard(
                title: "大文件",
                value: "\(result.largeFiles.count) 个",
                icon: "doc.fill",
                color: AppTheme.warning
            )
            StatCard(
                title: "重复组",
                value: "\(result.duplicateGroups.count) 组",
                icon: "doc.on.doc.fill",
                color: AppTheme.info
            )
        }
    }

    // MARK: - Recent Scan Info

    private func recentScanInfo(_ result: ScanResult) -> some View {
        HStack {
            Label("扫描时间: \(result.formattedScanDate)", systemImage: "clock")
            Spacer()
            Label("耗时: \(result.formattedDuration)", systemImage: "stopwatch")
            Spacer()
            Label("扫描 \(result.totalScannedFiles) 个文件", systemImage: "doc.text.magnifyingglass")
        }
        .font(.system(size: 11))
        .foregroundColor(AppTheme.textSecondary)
        .padding(12)
        .cardStyle()
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = AppTheme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Scanning Overlay

struct ScanningOverlay: View {
    let progress: Double
    let status: String

    var body: some View {
        ScanProgressOverlay(progress: progress, statusText: status)
    }
}
