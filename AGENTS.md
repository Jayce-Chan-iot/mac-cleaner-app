# MacCleanerApp — AI 项目规则手册

> 给下一个在此项目工作的 AI（无论 Codex、Codex 还是别的）快速理解项目。

## 项目概要

macOS 原生文件分类整理 + 垃圾文件清理工具。SwiftUI GUI，面向普通用户，安全优先。

## 技术约束（硬规则）

- **语言**: Swift 6（严格并发检查 `Complete`）
- **UI 框架**: SwiftUI（macOS 14+）
- **架构**: MVVM，单体多模块，`NavigationSplitView` 三栏布局
- **包管理**: Swift Package Manager（`Package.swift`）；外部依赖版本锁定用 `from: "x.y.z"` 而非 `branch: "main"`
- **构建**: `swift build`（无需 Xcode 即可编译；运行需 Xcode 16+）。⚠️ DynamicNotchKit v1.1.0 使用 `@Entry`/`#Preview` 宏，仅 Xcode 工具链支持，CLI-only Swift 需先执行 `bash scripts/build-dmg.sh` 中的自动修复或手动替换 `EnvironmentValues+Extensions.swift` 和 `NotchShape.swift`
- **暗色主题**: 只支持暗色 HUD 风格，配色见 `UI/Theme/AppTheme.swift`
- **删除安全红线**: 用户删除走 `TrashManager.moveToTrash()`（应用回收站 7 天）→ 过期走 `trashItem`（系统废纸篓 30 天）。全流程零 `removeItem` 调用（仅 TrashManager 对已验证为空的元数据目录用 `removeItem`）
- **白名单**: `/System`、`/bin`、`/sbin`、`/usr/lib` 等硬编码排除（见 `SafetyManager`）
- **内存红线**: 运行时 < 200MB（目标 ~100MB）。禁止一次性物化全量文件列表；所有文件遍历必须流式 + 批处理释放
- **测试**: XCTest（35 用例 / 6 类），CI 用 GitHub Actions macos-15 runner。`#if DEBUG` 用于暴露测试专用 API。安全测试优先于功能测试

## 项目结构速查

```
Sources/MacCleanerApp/
├── App/                    # @main 入口 + NavigationSplitView 布局
│   ├── MacCleanerApp.swift # AppState（@MainActor）+ Module 枚举（9 个）
│   └── ContentView.swift   # 侧边栏 + 模块路由
├── Models/
│   ├── FileItem.swift      # 文件条目 + FileCategory 枚举（8 类 + 扩展名映射）
│   ├── ScanResult.swift    # 扫描结果聚合 + DuplicateGroup + DiskInfo
│   ├── JunkCategory.swift  # 12 类垃圾 + SafetyLevel（safe/caution/expert）
│   ├── TrashItem.swift     # ★ 回收站条目（Codable, Identifiable, Sendable）
│   └── InstalledApp.swift  # ★ 已安装应用（Bundle ID + 版本 + 残留文件列表）
├── Services/               # 全部用 actor 实现（Swift 6 并发安全）
│   ├── SafetyManager.swift # 白名单检查 + trashItem + 操作日志（nonisolated isProtected）
│   ├── UnifiedScanner.swift # ★ 统一流式扫描（一次遍历四路分流：垃圾/大文件/重复/分类）
│   ├── FileScanner.swift   # 磁盘信息获取
│   ├── JunkDetector.swift  # 22 条内置扫描规则 + Glob 模式匹配（nonisolated rules）
│   ├── DuplicateDetector.swift # 三级哈希过滤（大小→前置→全文件 SHA-256）
│   ├── SystemMonitor.swift # CPU/内存实时监控（host_processor_info + host_statistics64）
│   ├── TrashManager.swift  # ★ 应用回收站（7 天保留 + 恢复 + 定时清理 + 崩溃恢复）
│   ├── ProcessManager.swift # ★ 进程管理（NSWorkspace + proc_pidinfo + SIGTERM/SIGKILL）
│   └── AppUninstaller.swift # ★ 软件卸载（12 路径 Bundle ID 残留扫描 + Pearcleaner 引擎）
├── UI/
│   ├── Theme/              # AppTheme（颜色/字体/Card）+ ColorPalette（类别→颜色映射）
│   └── Components/         # RadialBarChart, TreeMapChart, FileRowView, DynamicIslandController
│       ├── MenuBarController.swift  # ⚠️ DEPRECATED v0.3
│       ├── SunburstChart.swift      # ⚠️ DEPRECATED v0.4 → RadialBarChart
│       └── OrbitalView.swift        # ⚠️ DEPRECATED v0.4
└── Modules/
    ├── Dashboard/          # 磁盘概览环形图 + 一键扫描 + 统计卡片
    ├── FileClassifier/     # 辐射状柱状图 + 底部图例
    ├── JunkCleaner/        # 三级折叠面板 + 删除确认弹窗 → 回收站 + 灵动岛通知
    ├── LargeFileFinder/    # 大小/时间筛选 + 删除确认弹窗 → 回收站
    ├── DuplicateFinder/    # 重复组卡片 + 删除确认弹窗 → 回收站
    ├── DiskAnalyzer/       # 辐射图 + 柱状图 + 树图 + ScrollView（UnifiedScanner 四路管道）
    ├── TrashBin/           # ★ 回收站：文件列表 + 倒计时 + 批量恢复/彻底删除
    ├── ProcessManager/     # ★ 进程管理：搜索 + 筛选 + 终止（SIGTERM→SIGKILL）
    └── AppUninstaller/     # ★ 软件卸载：残留分析 + 确认弹窗 → 回收站
└── Tests/
    └── MacCleanerAppTests/  # XCTest 安全测试套件（35 用例 / 6 类）
```

## 命名与代码约定

- **Model 文件**: 单一 struct/enum 即可，不拆分微小 Type
- **Service actor**: 所有文件操作经由 actor，外部一律 `await`
- **View**: 每个模块一个 View 文件（含 Sheet/Overlay），不拆分细小 subview
- **@MainActor**: `AppState` 用 `@MainActor + @unchecked Sendable`
- **闭包进度回调**: 参数标记 `@Sendable`（Swift 6 要求）
- **NSEnumerator**: 禁止 `.allObjects`（内存炸弹，见 memory 红线），必须流式 for-in + `autoreleasepool` + 每 500 个冲刷缓冲区
- **删除分流模式**: 同步方法设 `pendingDeleteURLs` + `showDeleteConfirmation = true` → Alert confirm → async `executeDelete()` → Alert result。JunkCleaner/LargeFileFinder/DuplicateFinder/AppUninstaller 四处统一
- **进程终止**: GUI 应用走 `NSRunningApplication.terminate()` → 3s → `forceTerminate()`；后台进程走 `kill(pid, SIGTERM)` → 3s → `kill(pid, SIGKILL)`。系统进程（Dock/WindowServer/loginwindow/Finder/mds/kernel_task）白名单禁止终止

## 命令速查

```bash
swift build                          # 编译（不需要 Xcode）
swift test                           # 运行测试（需要 Xcode.app 提供 XCTest SDK）
swift run                            # 运行（需要 Xcode.app 提供 macOS SDK）
swift package generate-xcodeproj     # 生成 Xcode 项目文件
bash scripts/build-dmg.sh            # 一键构建 .app + .dmg（Universal Binary）
```

## 参考对标项目

| 模块 | 参考 |
|------|------|
| JunkDetector | PureMac (4.4k★), MacSift (9★) |
| UnifiedScanner | 自研（Czkawka 三级哈希 + PureMac 规则 + 流式批处理） |
| DuplicateDetector | Czkawka (31k★) 三级哈希算法 |
| FileScanner | Pearcleaner (13k★) GCD 并发 |
| SunburstChart | DodoTidy (174★) SectorMark |
| SystemMonitor | IOKit + host_statistics（参考 Stats/istat-menus） |
| Dashboard | PureMac Dashboard 磁盘信息 |
| DynamicIslandController | DynamicNotchKit (182★) MIT license, SPM 包 |
| TrashManager | 自研（二级回收站 + manifest + 崩溃恢复） |
| ProcessManager | 自研（NSWorkspace + libproc proc_pidinfo 差分 CPU） |
| AppUninstaller | Pearcleaner (13k★) Bundle ID 残留扫描引擎 |
| RadialBarChart | 自研（极坐标辐射状柱状图，替代 DodoTidy SectorMark Sunburst） |

## 深入文档

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 完整架构设计、模块详设、安全设计 |
| [README.md](README.md) | 安装与使用指南（给人类读者） |
