// DEPRECATED in v0.3 — replaced by DynamicIslandController.swift
import SwiftUI

/// 菜单栏系统状态显示 — 刘海左侧：温度 · 刘海右侧：CPU + RAM
/// NSStatusBar 嵌入菜单栏原生区域，不遮挡任何应用窗口
@MainActor
final class MenuBarController: ObservableObject {
    static let shared = MenuBarController()

    private var cpuItem: NSStatusItem?
    private var ramItem: NSStatusItem?

    private let monitor = SystemMonitor()
    private var timer: Timer?

    private init() {}

    func start() {
        // CPU 使用率
        cpuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = cpuItem?.button {
            button.title = "⚡ --%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }

        // 内存使用率
        ramItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = ramItem?.button {
            button.title = "🧠 --%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }

        // 初刷新
        Task { await refresh() }

        // 每 2 秒刷新
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let item = cpuItem {
            NSStatusBar.system.removeStatusItem(item)
            cpuItem = nil
        }
        if let item = ramItem {
            NSStatusBar.system.removeStatusItem(item)
            ramItem = nil
        }
    }

    private func refresh() async {
        let stats = await monitor.snapshot()

        let cpuPct = Int(stats.cpuUsage * 100)
        let ramPct = Int(stats.memoryUsagePercent * 100)

        cpuItem?.button?.title = String(format: "⚡ %d%%", cpuPct)
        ramItem?.button?.title = String(format: "🧠 %d%%", ramPct)

        // 颜色提示（通过 attributedTitle）
        cpuItem?.button?.attributedTitle = attributedStatus(
            icon: "⚡", percent: cpuPct, warm: 50, hot: 80
        )
        ramItem?.button?.attributedTitle = attributedStatus(
            icon: "🧠", percent: ramPct, warm: 60, hot: 85
        )
    }

    private func attributedStatus(icon: String, percent: Int, warm: Int, hot: Int) -> NSAttributedString {
        let color: NSColor
        if percent < warm {
            color = NSColor(red: 0, green: 0.83, blue: 0.67, alpha: 1) // 绿色 = 正常
        } else if percent < hot {
            color = NSColor(red: 1, green: 0.72, blue: 0, alpha: 1) // 橙色 = 温热
        } else {
            color = NSColor(red: 1, green: 0.42, blue: 0.42, alpha: 1) // 红色 = 繁忙
        }
        return NSAttributedString(
            string: String(format: "\(icon) %d%%", percent),
            attributes: [.foregroundColor: color, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]
        )
    }
}
