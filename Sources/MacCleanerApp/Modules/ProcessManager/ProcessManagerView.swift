import SwiftUI

struct ProcessManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var processes: [ProcessItem] = []
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var showKillConfirm = false
    @State private var targetProcess: ProcessItem?
    @State private var killResult: String?
    @State private var showResult = false

    private let manager = ProcessManager()
    @State private var isVisible = true
    private var timer: Timer.TimerPublisher {
        Timer.publish(every: 2, on: .main, in: .common)
    }

    private enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case gui = "GUI 应用"
        case background = "后台进程"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("进程管理")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("查看和管理系统中运行的程序和后台进程")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Button { Task { await refresh() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.bordered).tint(AppTheme.textSecondary)
            }

            // Search + Filter
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(AppTheme.textSecondary)
                    TextField("搜索进程...", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(8).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { Label($0.rawValue, systemImage: "line.3.horizontal.decrease").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 260)
            }

            // Summary
            HStack(spacing: 16) {
                StatCard(title: "总进程", value: "\(processes.count)", icon: "cpu", color: AppTheme.accent)
                StatCard(title: "GUI 应用", value: "\(processes.filter(\.isGUIApp).count)", icon: "app.fill", color: AppTheme.info)
                StatCard(title: "后台进程", value: "\(processes.filter { !$0.isGUIApp }.count)", icon: "gearshape.2", color: AppTheme.warning)
            }

            // Table header
            HStack(spacing: 10) {
                Text("进程名").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textSecondary).frame(width: 55, alignment: .trailing)
                Text("内存").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textSecondary).frame(width: 70, alignment: .trailing)
                Text("PID").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textSecondary).frame(width: 50, alignment: .trailing)
                Text("操作").font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textSecondary).frame(width: 40, alignment: .center)
            }
            .padding(.horizontal, 10)

            // Process list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredProcesses, id: \.id) { proc in
                        processRow(proc)
                    }
                }
            }
        }
        .padding(24)
        .onReceive(timer) { _ in
            guard isVisible else { return }
            Task { await refresh() }
        }
        .onAppear { isVisible = true; Task { await refresh() } }
        .onDisappear { isVisible = false; processes = [] }
        .alert("终止进程", isPresented: $showKillConfirm) {
            Button("取消", role: .cancel) {}
            Button("强制终止", role: .destructive) {
                Task { await killTarget() }
            }
        } message: {
            Text("确定要终止「\(targetProcess?.name ?? "")」吗？未保存的数据可能丢失。")
        }
        .alert("操作结果", isPresented: $showResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(killResult ?? "")
        }
    }

    // MARK: - Process Row

    private func processRow(_ proc: ProcessItem) -> some View {
        HStack(spacing: 10) {
            if let bundleID = proc.bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().frame(width: 20, height: 20)
            } else if proc.isGUIApp {
                Image(systemName: "app.fill").frame(width: 20).foregroundColor(AppTheme.textSecondary)
            } else {
                Image(systemName: "gearshape").frame(width: 20).foregroundColor(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(proc.name).font(.system(size: 13, weight: .medium)).foregroundColor(AppTheme.textPrimary).lineLimit(1)
                Text("PID \(proc.id)\(proc.bundleIdentifier.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10)).foregroundColor(AppTheme.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", proc.cpuPercent))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(proc.cpuPercent > 50 ? AppTheme.danger : AppTheme.textPrimary)
                .frame(width: 55, alignment: .trailing)

            Text(formatMemory(proc.memoryBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)

            Text("\(proc.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 50, alignment: .trailing)

            Button {
                targetProcess = proc
                showKillConfirm = true
            } label: {
                Image(systemName: proc.isSystemProcess ? "lock.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(proc.isSystemProcess ? AppTheme.textSecondary : AppTheme.danger)
            }
            .buttonStyle(.plain)
            .disabled(proc.isSystemProcess)
            .frame(width: 40)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private var filteredProcesses: [ProcessItem] {
        let modeFiltered: [ProcessItem] = {
            switch filterMode {
            case .all: return processes
            case .gui: return processes.filter(\.isGUIApp)
            case .background: return processes.filter { !$0.isGUIApp }
            }
        }()
        if searchText.isEmpty { return modeFiltered }
        return modeFiltered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func refresh() async {
        processes = await manager.runningProcesses()
    }

    private func killTarget() async {
        guard let target = targetProcess else { return }
        let success: Bool
        if target.isGUIApp {
            success = await manager.terminateGUIApp(pid: target.id)
        } else {
            success = manager.killProcess(pid: target.id)
        }
        killResult = success ? "已终止「\(target.name)」" : "终止「\(target.name)」失败"
        showResult = true
        await refresh()
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
