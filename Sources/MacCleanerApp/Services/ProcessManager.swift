import AppKit
import Darwin

// MARK: - Process Info Model

struct ProcessItem: Identifiable, Sendable {
    let id: Int32
    let name: String
    let bundleIdentifier: String?
    let isGUIApp: Bool
    let cpuPercent: Double
    let memoryBytes: UInt64
    var isSystemProcess: Bool {
        let systemNames: Set<String> = ["Dock", "WindowServer", "loginwindow", "SystemUIServer", "Finder",
                                         "mds", "mdsync", "mdworker", "kernel_task", "launchd"]
        return systemNames.contains(name) || bundleIdentifier?.hasPrefix("com.apple") == true
    }
}

// MARK: - Process Manager

actor ProcessManager {
    private var previousCPUTicks: [Int32: (user: UInt64, system: UInt64, timestamp: UInt64)] = [:]

    func runningProcesses() -> [ProcessItem] {
        let apps = NSWorkspace.shared.runningApplications
        var results: [ProcessItem] = []
        let now = mach_absolute_time()

        for app in apps {
            let pid = app.processIdentifier
            let cpu = calculateCPU(for: pid, now: now)
            let mem = residentMemory(for: pid)
            let item = ProcessItem(
                id: pid,
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                isGUIApp: app.activationPolicy == .regular || app.activationPolicy == .accessory,
                cpuPercent: cpu,
                memoryBytes: mem
            )
            results.append(item)
        }
        return results.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    func terminateGUIApp(pid: Int32) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.terminate() { return true }
        try? await Task.sleep(for: .seconds(3))
        return app.forceTerminate()
    }

    nonisolated func killProcess(pid: Int32) -> Bool {
        if kill(pid, SIGTERM) == 0 { return true }
        usleep(3_000_000)
        return kill(pid, SIGKILL) == 0
    }

    private func calculateCPU(for pid: Int32, now: UInt64) -> Double {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result > 0 else { return 0 }
        let currentUser = info.pti_total_user
        let currentSystem = info.pti_total_system
        defer { previousCPUTicks[pid] = (user: currentUser, system: currentSystem, timestamp: now) }
        guard let prev = previousCPUTicks[pid] else { return 0 }
        let userDelta = currentUser - prev.user
        let sysDelta = currentSystem - prev.system
        let timeDelta = Double(now - prev.timestamp)
        guard timeDelta > 0 else { return 0 }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = timeDelta * Double(timebase.numer) / Double(timebase.denom)
        let cpuPct = Double(userDelta + sysDelta) / nanos * 100.0
        return min(cpuPct, 100.0)
    }

    private func residentMemory(for pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result > 0 else { return 0 }
        return info.pti_resident_size
    }
}
