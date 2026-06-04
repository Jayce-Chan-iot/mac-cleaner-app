import SwiftUI

/// App 入口 —— 参考 PureMac 和 Pearcleaner 的 SwiftUI 生命周期
@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 650)
                .preferredColorScheme(.dark)
                .task {
                    await appState.trashManager.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // 自定义菜单
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("操作日志") {
                    appState.showOperationLog.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

/// 全局应用状态（@MainActor 确保线程安全）
@MainActor
class AppState: ObservableObject, @unchecked Sendable {
    @Published var selectedModule: Module = .dashboard
    @Published var showOperationLog = false
    @Published var lastScanDate: Date?
    @Published var totalCleanedSize: Int64 = 0
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanStatusText: String = ""

    /// 最近一次扫描结果（nil 表示尚未扫描）
    @Published var lastScanResult: ScanResult?

    /// 后台扫描任务（nil = 未在扫描），AppState 全生命周期，切页不中断
    private var scanTask: Task<Void, Never>? = nil

    /// 扫描引擎
    let fileScanner = FileScanner()
    let safetyManager = SafetyManager()
    let trashManager = TrashManager()

    var formattedCleanedSize: String {
        ByteCountFormatter.string(fromByteCount: totalCleanedSize, countStyle: .file)
    }

    /// 启动一键扫描（不阻塞，切页不中断）
    @MainActor
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        scanStatusText = "准备扫描..."

        scanTask = Task { @MainActor in
            await self.executeScan()
        }
    }

    /// 实际扫描逻辑（由 scanTask 持有，View 生命周期无关）
    @MainActor
    private func executeScan() async {
        let startTime = Date()
        let scanner = UnifiedScanner()

        do {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            let diskInfo = try await fileScanner.getDiskInfo(for: homeURL)

            let (junkResults, largeFiles, duplicates, _) = try await scanner.scan(
                rootURL: homeURL,
                progressHandler: { status, progress in
                    Task { @MainActor in
                        self.scanStatusText = status
                        self.scanProgress = progress
                    }
                }
            )

            scanStatusText = "生成报告..."
            let duration = Date().timeIntervalSince(startTime)

            let totalJunkSize = junkResults.values.flatMap { $0 }.reduce(0 as Int64) { $0 + $1.size }
            let totalJunkCount = junkResults.values.flatMap { $0 }.count

            let result = ScanResult(
                scanDate: Date(),
                scanDuration: duration,
                totalScannedFiles: totalJunkCount,
                totalScannedSize: totalJunkSize,
                categorizedFiles: [:],
                junkFiles: junkResults,
                largeFiles: largeFiles,
                duplicateGroups: duplicates,
                diskInfo: diskInfo
            )

            self.lastScanResult = result
            self.lastScanDate = Date()
            self.scanProgress = 1.0
            self.scanStatusText = "扫描完成！"

            DynamicIslandController.shared.showScanComplete(
                fileCount: totalJunkCount,
                duration: duration
            )

            if self.selectedModule != .dashboard {
                self.selectedModule = .dashboard
            }

        } catch {
            self.scanStatusText = "扫描失败: \(error.localizedDescription)"
        }

        self.isScanning = false
    }

    /// 取消正在进行的扫描
    @MainActor
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanStatusText = "扫描已取消"
    }
}

/// 侧边栏导航模块
enum Module: String, CaseIterable, Identifiable {
    case dashboard
    case fileClassifier
    case junkCleaner
    case largeFileFinder
    case duplicateFinder
    case diskAnalyzer
    case trashBin
    case processManager
    case appUninstaller

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .fileClassifier: return "文件分类"
        case .junkCleaner: return "垃圾清理"
        case .largeFileFinder: return "大文件查找"
        case .duplicateFinder: return "重复文件检测"
        case .diskAnalyzer: return "磁盘分析"
        case .trashBin: return "回收站"
        case .processManager: return "进程管理"
        case .appUninstaller: return "软件卸载"
        }
    }

    var iconName: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .fileClassifier: return "folder.fill.badge.gearshape"
        case .junkCleaner: return "trash.fill"
        case .largeFileFinder: return "doc.fill.badge.ellipsis"
        case .duplicateFinder: return "doc.on.doc.fill"
        case .diskAnalyzer: return "chart.pie.fill"
        case .trashBin: return "trash.slash"
        case .processManager: return "cpu"
        case .appUninstaller: return "xmark.bin.fill"
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DynamicIslandController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DynamicIslandController.shared.stop()
    }
}
