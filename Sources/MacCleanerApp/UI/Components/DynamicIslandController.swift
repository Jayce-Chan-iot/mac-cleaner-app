import SwiftUI
import DynamicNotchKit

/// 灵动岛菜单栏控制器 — 混合模式（D）：常驻胶囊 + 事件弹窗 + RAM 进程管理
@MainActor
final class DynamicIslandController: ObservableObject {
    static let shared = DynamicIslandController()

    private let monitor = SystemMonitor()
    private let processManager = ProcessManager()
    private var timer: Timer?
    private var currentNotch: DynamicNotch<NotchHUDView, CompactCPUView, CompactRAMView>?
    private var ramPanelNotch: DynamicNotch<RAMTopProcessView, EmptyView, EmptyView>?
    private var eventNotch: DynamicNotchInfo?
    private var highCPUStartTime: Date?
    private var highCPUNotified = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .showRAMProcessPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.toggleRAMPanel()
            }
        }
    }

    // MARK: - Start / Stop

    func start() {
        let notch = DynamicNotch {
            NotchHUDView()
        } compactLeading: {
            CompactCPUView()
        } compactTrailing: {
            CompactRAMView()
        }
        // 展开 → 3 秒后自动收缩
        Task {
            await notch.expand()
            try? await Task.sleep(for: .seconds(3))
            await notch.compact()
        }
        currentNotch = notch

        Task { await refresh() }

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 悬停检测：悬停展开，移开 2s 后收缩
        Task {
            while !Task.isCancelled {
                if let n = currentNotch, n.isHovering {
                    await n.expand()
                    // 等待直到不再悬停
                    while currentNotch?.isHovering == true {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    // 移开后等 2 秒再收缩
                    try? await Task.sleep(for: .seconds(2))
                    if currentNotch?.isHovering == false {
                        await currentNotch?.compact()
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let notch = currentNotch {
            Task { await notch.hide() }
        }
        currentNotch = nil
    }

    // MARK: - Refresh

    private func refresh() async {
        let stats = await monitor.snapshot()
        let cpuPct = Int(stats.cpuUsage * 100)
        let ramPct = Int(stats.memoryUsagePercent * 100)

        NotchHUDData.shared.cpuPercent = cpuPct
        NotchHUDData.shared.ramPercent = ramPct

        if cpuPct > 80 {
            if highCPUStartTime == nil {
                highCPUStartTime = Date()
            } else if !highCPUNotified,
                      let start = highCPUStartTime,
                      Date().timeIntervalSince(start) > 10 {
                highCPUNotified = true
                showCPUWarning(cpuPercent: cpuPct)
            }
        } else {
            highCPUStartTime = nil
            highCPUNotified = false
        }
    }

    // MARK: - Event Notifications

    func showScanComplete(fileCount: Int, duration: TimeInterval) {
        let notch = DynamicNotchInfo(
            icon: DynamicNotchInfo.Label(systemName: "magnifyingglass"),
            title: "扫描完成",
            description: "发现 \(fileCount) 个文件，耗时 \(String(format: "%.0f", duration)) 秒"
        )
        eventNotch = notch
        Task {
            await notch.expand()
            try? await Task.sleep(for: .seconds(4))
            await notch.hide()
            self.eventNotch = nil
        }
    }

    func showCleanComplete(freedSize: String) {
        let notch = DynamicNotchInfo(
            icon: DynamicNotchInfo.Label(systemName: "trash"),
            title: "清理完成",
            description: "已释放 \(freedSize)，文件在回收站保留 7 天"
        )
        eventNotch = notch
        Task {
            await notch.expand()
            try? await Task.sleep(for: .seconds(4))
            await notch.hide()
            self.eventNotch = nil
        }
    }

    private func showCPUWarning(cpuPercent: Int) {
        let notch = DynamicNotchInfo(
            icon: DynamicNotchInfo.Label(systemName: "exclamationmark.triangle"),
            title: "CPU 使用率偏高",
            description: "当前 CPU 占用 \(cpuPercent)%，建议检查后台进程"
        )
        eventNotch = notch
        Task {
            await notch.expand()
            try? await Task.sleep(for: .seconds(5))
            await notch.hide()
            self.eventNotch = nil
        }
    }

    // MARK: - RAM Process Panel (D Mode)

    private func toggleRAMPanel() async {
        if ramPanelNotch != nil {
            await ramPanelNotch?.hide()
            ramPanelNotch = nil
            return
        }

        let procs = await processManager.runningProcesses()
        let top5 = Array(procs.filter { !$0.isSystemProcess }.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
        await MainActor.run { RAMTopProcessData.shared.processes = top5 }

        let panel = DynamicNotch {
            RAMTopProcessView()
        }
        ramPanelNotch = panel
        await panel.expand()

        // Auto-hide after 8 seconds
        Task {
            try? await Task.sleep(for: .seconds(8))
            await panel.hide()
            await MainActor.run { self.ramPanelNotch = nil }
        }
    }
}

// MARK: - RAM Panel Data

@MainActor
final class RAMTopProcessData: ObservableObject {
    static let shared = RAMTopProcessData()
    @Published var processes: [ProcessItem] = []
}

// MARK: - RAM Top Process View

struct RAMTopProcessView: View {
    @ObservedObject private var data = RAMTopProcessData.shared
    private let manager = ProcessManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内存占用 Top 5").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Divider().background(Color.white.opacity(0.2))

            ForEach(data.processes, id: \.id) { proc in
                HStack(spacing: 8) {
                    Image(systemName: proc.isGUIApp ? "app.fill" : "gearshape")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
                    Text(proc.name).font(.system(size: 12)).foregroundColor(.white).lineLimit(1)
                    Spacer()
                    Text(formatBytes(proc.memoryBytes))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    Button {
                        Task {
                            if proc.isGUIApp {
                                _ = await manager.terminateGUIApp(pid: proc.id)
                            } else {
                                _ = manager.killProcess(pid: proc.id)
                            }
                            // Refresh list
                            let procs = await manager.runningProcesses()
                            let top5 = Array(procs.filter { !$0.isSystemProcess }
                                .sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
                            await MainActor.run { data.processes = top5 }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14)).foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if data.processes.isEmpty {
                Text("正在加载...").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }

            HStack {
                Spacer()
                Text("打开完整进程管理 →").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let showRAMProcessPanel = Notification.Name("showRAMProcessPanel")
}

// MARK: - CompactRAMView (clickable)

struct CompactRAMView: View {
    @ObservedObject private var data = NotchHUDData.shared
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .showRAMProcessPanel, object: nil)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(ramColor).frame(width: 5, height: 5)
                Text("\(data.ramPercent)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }.padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }
    private var ramColor: Color {
        if data.ramPercent < 60 { return .green }
        if data.ramPercent < 85 { return .orange }
        return .red
    }
}

// MARK: - Shared HUD Data

@MainActor
final class NotchHUDData: ObservableObject {
    static let shared = NotchHUDData()
    @Published var cpuPercent: Int = 0
    @Published var ramPercent: Int = 0
}

// MARK: - Notch HUD View

struct NotchHUDView: View {
    @ObservedObject private var data = NotchHUDData.shared

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(cpuColor)
                    .frame(width: 6, height: 6)
                Text("CPU")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                Text("\(data.cpuPercent)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 12)

            Button {
                NotificationCenter.default.post(name: .showRAMProcessPanel, object: nil)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ramColor)
                        .frame(width: 6, height: 6)
                    Text("RAM")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                    Text("\(data.ramPercent)%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var cpuColor: Color {
        if data.cpuPercent < 50 { return .green }
        if data.cpuPercent < 80 { return .orange }
        return .red
    }

    private var ramColor: Color {
        if data.ramPercent < 60 { return .green }
        if data.ramPercent < 85 { return .orange }
        return .red
    }
}

// MARK: - Compact Views (刘海两侧)

struct CompactCPUView: View {
    @ObservedObject private var data = NotchHUDData.shared
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(cpuColor).frame(width: 5, height: 5)
            Text("\(data.cpuPercent)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }.padding(.horizontal, 6)
    }
    private var cpuColor: Color {
        if data.cpuPercent < 50 { return .green }
        if data.cpuPercent < 80 { return .orange }
        return .red
    }
}

