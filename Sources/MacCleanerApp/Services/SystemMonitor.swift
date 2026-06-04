import Foundation

/// 系统状态监控 — CPU 使用率、内存使用量
/// 温度读取需要 SMC 协议，先用占位值；后续可接入 SMCKit 或 powermetrics
actor SystemMonitor {
    private var lastCPUTick: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    struct SystemStats: Sendable {
        let cpuUsage: Double      // 0.0–1.0
        let memoryUsed: UInt64    // bytes
        let memoryTotal: UInt64   // bytes

        var memoryUsagePercent: Double {
            guard memoryTotal > 0 else { return 0 }
            return Double(memoryUsed) / Double(memoryTotal)
        }
    }

    // MARK: - CPU (host_processor_info)

    func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        guard host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        ) == KERN_SUCCESS else { return 0 }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.size)
            )
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCpus) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        let current = (user: totalUser, system: totalSystem, idle: totalIdle, nice: totalNice)
        defer { lastCPUTick = current }

        guard let prev = lastCPUTick else { return 0 }

        let prevTotal = prev.user + prev.system + prev.idle + prev.nice
        let currTotal = current.user + current.system + current.idle + current.nice
        let delta = currTotal - prevTotal

        guard delta > 0 else { return 0 }

        let usedDelta = (current.user - prev.user) + (current.system - prev.system) + (current.nice - prev.nice)
        return Double(usedDelta) / Double(delta)
    }

    // MARK: - Memory (host_statistics64)

    func getMemoryStats() -> (used: UInt64, total: UInt64) {
        var info = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let total = info.max_mem

        // 获取实际使用内存
        let pageSize = UInt64(sysconf(Int32(_SC_PAGESIZE)))

        var vmStat = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let vmResult = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        guard vmResult == KERN_SUCCESS else { return (0, total) }

        // App 内存 + 联动内存 = 最接近活动监视器的"已用内存"
        let used = (UInt64(vmStat.active_count)
            + UInt64(vmStat.wire_count)
            + UInt64(vmStat.speculative_count)) * pageSize

        return (used, total)
    }

    // MARK: - Snapshot

    func snapshot() -> SystemStats {
        let cpu = getCPUUsage()
        let (memUsed, memTotal) = getMemoryStats()
        return SystemStats(cpuUsage: cpu, memoryUsed: memUsed, memoryTotal: memTotal)
    }
}
