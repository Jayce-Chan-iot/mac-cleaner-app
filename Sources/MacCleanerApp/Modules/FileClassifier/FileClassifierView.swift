import SwiftUI

/// 文件分类视图 —— Sunburst 旭日图 + 轨道交互
struct FileClassifierView: View {
    @EnvironmentObject var appState: AppState

    @State private var categorizedFiles: [FileItem.FileCategory: [FileItem]] = [:]
    @State private var isLoading = false
    @State private var radialBarData: RadialBarData?

    var body: some View {
        VStack(spacing: 16) {
            ModuleHeader(
                title: "文件分类",
                icon: "folder.fill.badge.gearshape",
                action: { Task { await scanFiles() } },
                actionLabel: "扫描文件"
            )

            if isLoading {
                Spacer()
                ProgressView("正在扫描文件...")
                    .font(.system(size: 14))
                Spacer()
            } else if let data = radialBarData, !data.bars.isEmpty {
                RadialBarChart(data: data)
                    .frame(height: 450)

                // 图例
                legendView
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "circle.hexagonpath")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("点击「扫描文件」对 Home 目录进行分类分析")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            }
        }
        .padding(24)
    }

    private func scanFiles() async {
        isLoading = true
        let scanner = FileScanner()

        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            categorizedFiles = try await scanner.scanDirectory(home)
            radialBarData = RadialBarData.build(from: categorizedFiles)
        } catch {
            // 处理错误
        }

        isLoading = false
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(FileItem.FileCategory.allCases) { category in
                    let count = categorizedFiles[category]?.count ?? 0
                    let size = categorizedFiles[category]?.reduce(0 as Int64) { $0 + $1.size } ?? 0
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ColorPalette.color(for: category))
                                .frame(width: 8, height: 8)
                            Text(category.rawValue)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .cardStyle()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FileClassifierView_Previews: PreviewProvider {
    static var previews: some View {
        FileClassifierView()
            .environmentObject(AppState())
    }
}
#endif
