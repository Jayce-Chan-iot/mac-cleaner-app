import SwiftUI

struct AppUninstallerView: View {
    @EnvironmentObject var appState: AppState
    @State private var apps: [InstalledApp] = []
    @State private var selectedApp: InstalledApp?
    @State private var isLoading = false
    @State private var isAnalyzing = false
    @State private var showConfirm = false
    @State private var uninstallResult: String?
    @State private var showResult = false

    private let uninstaller = AppUninstaller()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("软件卸载")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("卸载应用并清理残留文件")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                if selectedApp != nil {
                    Button { selectedApp = nil } label: {
                        Label("返回列表", systemImage: "chevron.left").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).tint(AppTheme.textSecondary)
                }
                Button { Task { await scan() } } label: {
                    Label("扫描应用", systemImage: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.bordered).tint(AppTheme.textSecondary)
            }

            if isLoading {
                Spacer()
                ProgressView("正在扫描应用...")
                Spacer()
            } else if let app = selectedApp {
                orphanDetailView(app)
            } else if apps.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "xmark.bin").font(.system(size: 48)).foregroundColor(AppTheme.textSecondary)
                    Text("点击「扫描应用」查看已安装的应用").font(.system(size: 14)).foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(apps) { app in appRow(app) }
                    }
                }
            }
        }
        .padding(24)
        .task { await scan() }
        .alert("确认卸载", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("移入回收站", role: .destructive) {
                Task { await executeUninstall() }
            }
        } message: {
            Text("确定要卸载「\(selectedApp?.name ?? "")」吗？\n应用及所有残留文件将移入回收站，保留 7 天。")
        }
        .alert("卸载结果", isPresented: $showResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(uninstallResult ?? "")
        }
    }

    // MARK: - App Row

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                .resizable().frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.textPrimary)
                Text("v\(app.version ?? "?") · \(app.bundleID)")
                    .font(.system(size: 10)).foregroundColor(AppTheme.textSecondary).lineLimit(1)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: app.appSize, countStyle: .file))
                .font(.system(size: 12, design: .monospaced)).foregroundColor(AppTheme.textSecondary)

            Button {
                Task { await analyzeOrphans(for: app) }
            } label: {
                Label("分析残留", systemImage: "magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered).tint(AppTheme.accent)
        }
        .padding(12)
        .background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Orphan Detail

    private func orphanDetailView(_ app: InstalledApp) -> some View {
        VStack(spacing: 16) {
            // App info header
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                    .resizable().frame(width: 64, height: 64)
                Text(app.name).font(.system(size: 18, weight: .bold)).foregroundColor(AppTheme.textPrimary)
                Text("v\(app.version ?? "?") · \(app.bundleID)")
                    .font(.system(size: 11)).foregroundColor(AppTheme.textSecondary)
            }

            if isAnalyzing {
                Spacer()
                ProgressView("正在扫描残留文件...")
                Spacer()
            } else {
                // File list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // App itself
                        fileRow(app.appURL, label: "应用本体 (\(app.appURL.lastPathComponent))", size: app.appSize)

                        // Orphans section header
                        if !app.orphans.isEmpty {
                            Text("残留文件").font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.warning).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).padding(.horizontal, 4)
                        }

                        ForEach(app.orphans) { file in
                            fileRow(file.url, label: file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), size: file.size)
                        }
                    }
                }

                // Bottom bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("共 \(app.orphans.count + 1) 项").font(.system(size: 13)).foregroundColor(AppTheme.textPrimary)
                        Text("总计 \(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))")
                            .font(.system(size: 12)).foregroundColor(AppTheme.accent)
                    }
                    Spacer()
                    Button {
                        showConfirm = true
                    } label: {
                        Label("卸载", systemImage: "trash").font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent).tint(AppTheme.danger)
                }
                .padding(12).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))
            }
        }
    }

    private func fileRow(_ url: URL, label: String, size: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").foregroundColor(AppTheme.textSecondary).frame(width: 16)
            Text(label).font(.system(size: 11)).foregroundColor(AppTheme.textPrimary).lineLimit(1)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func scan() async {
        isLoading = true
        apps = await uninstaller.scanApps()
        isLoading = false
    }

    private func analyzeOrphans(for app: InstalledApp) async {
        guard selectedApp?.id != app.id else { return }
        isAnalyzing = true
        var updated = app
        updated.orphans = await uninstaller.scanOrphans(for: app.bundleID)
        selectedApp = updated
        isAnalyzing = false
    }

    private func executeUninstall() async {
        guard let app = selectedApp else { return }
        var urls = [app.appURL]
        urls.append(contentsOf: app.orphans.map(\.url))
        do {
            let items = try await appState.trashManager.moveToTrash(urls)
            uninstallResult = "\u{2705}「\(app.name)」已卸载，\(items.count) 个文件移入回收站，保留 7 天"
            selectedApp = nil
            await scan()
        } catch {
            uninstallResult = "卸载失败: \(error.localizedDescription)"
        }
        showResult = true
    }
}
