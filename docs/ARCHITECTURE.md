# MacCleanerApp 架构设计文档

> 最后更新: 2026-06-02 | 版本: v0.1.1

## 1. 概述

MacCleanerApp 是一个 macOS 原生桌面应用，面向普通用户提供文件分类整理与垃圾清理功能。应用采用 SwiftUI + MVVM 架构，所有核心服务以 Swift 6 actor 实现，保证并发安全。

### 1.1 设计目标

- **安全第一**: 永不永久删除文件，仅使用 `FileManager.trashItem(at:)`
- **普通用户友好**: 三级安全分级（🟢/🟡/🔴），让非技术用户也能放心清理
- **科技感 UI**: 暗色 HUD 主题 + RadialBarChart 辐射图 + TreeMapChart 树图
- **轻量级运行**: 运行时内存 < 200MB（目标 ~100MB），流式扫描 + 批处理释放
- **后台不中断**: 扫描 Task 由 AppState 全生命周期持有，切页不取消
- **不重复造轮子**: 参考 GitHub 成熟项目（Pearcleaner、PureMac、Czkawka 等）

### 1.2 技术栈

| 维度 | 选择 |
|------|------|
| 语言 | Swift 6 |
| UI | SwiftUI (macOS 14+) |
| 架构 | MVVM, 单体多模块 |
| 图表 | Swift Charts (SectorMark) + 自研 RadialBarChart / TreeMapChart |
| 并发 | Swift Concurrency (actor, TaskGroup, @MainActor) |
| 加密 | CryptoKit (SHA-256) |
| 包管理 | Swift Package Manager |

## 2. 模块架构

```
┌─────────────────────────────────────────────────────┐
│                    NavigationSplitView                │
│  ┌──────────┐  ┌──────────────────────────────────┐ │
│  │          │  │                                  │ │
│  │ Sidebar  │  │        Detail Content            │ │
│  │          │  │                                  │ │
│  │ 🏠 仪表盘 │  │  Dashboard / FileClassifier /    │ │
│  │ 📁 分类  │  │  JunkCleaner / LargeFileFinder /  │ │
│  │ 🗑️ 清理  │  │  DuplicateFinder / DiskAnalyzer / │ │
│  │ 📦 大文件│  │  TrashBin / ProcessManager /      │ │
│  │ 🔍 重复  │  │  AppUninstaller                  │ │
│  │ 📊 磁盘  │  │                                  │ │
│  │ ♻️ 回收站│  │                                  │ │
│  │ ⚡ 进程  │  │                                  │ │
│  │ 🗑️ 卸载  │  │                                  │ │
│  │          │  │                                  │ │
│  └──────────┘  └──────────────────────────────────┘ │
│               ┌────────────────────────────────────┐ │
│               │  Status Bar: 扫描时间 / 清理统计   │ │
│               └────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## 3. 数据模型

### 3.1 FileItem
核心文件条目。包含 URL、大小、日期、文件类型（8 大类：图片/视频/文档/音频/压缩包/应用/代码/其他）。每种类型有预定义扩展名列表用于自动分类。

### 3.2 JunkCategory
垃圾文件分类枚举，12 个类别按 **SafetyLevel** 分三级：
- 🟢 **safe**: 系统缓存、应用缓存、浏览器缓存、日志、废纸篓
- 🟡 **caution**: Xcode 垃圾、邮件附件、DMG 安装包、iOS 备份
- 🔴 **expert**: Homebrew 缓存、Docker 残留、开发包缓存

### 3.3 ScanResult
一次完整扫描的聚合结果，包含：分类文件、垃圾文件、大文件列表、重复组、磁盘信息。

### 3.4 DuplicateGroup
重复文件组，包含文件大小、SHA-256 前缀、文件列表。`wasteSize` 计算可释放空间（文件数-1）× 大小。

### 3.5 DiskInfo
磁盘容量信息，包含总量/可用/已用/卷名，`usagePercentage` 用于仪表盘环形图。

## 4. 服务层设计

### 4.1 SafetyManager (actor)
**职责**: 文件操作安全门控。
- 白名单检查（`isProtected`）
- 回收站删除（`trashItems`）— 外部唯一允许的删除入口
- 操作日志（`SafetyLogEntry` 记录每次操作的时间/动作/详情）

### 4.2 FileScanner (actor)
**职责**: 通用文件系统遍历。
- `scanDirectory`: 递归扫描目录，按 FileCategory 分类
- `findLargeAndOldFiles`: 按大小/时间筛选
- `getDiskInfo`: 获取卷容量信息
- 并发策略: `withThrowingTaskGroup` 批量并行处理目录

### 4.3 JunkDetector (actor)
**职责**: 垃圾文件识别。
- 22 条内置扫描规则，每条指定 `(JunkCategory, baseURL, globPattern?)`
- 支持 Glob 模式匹配（通配符 `*` 用于容器化应用的缓存路径）
- 参考 PureMac 的分类逻辑 + MacSift 的按 App 分组思路

### 4.4 DuplicateDetector (actor)
**职责**: 重复文件检测（Czkawka 算法）。
- **第 1 级**: 按文件大小分组，过滤唯一大小
- **第 2 级**: 同大小文件计算前 4KB SHA-256 哈希
- **第 3 级**: 前哈希匹配的，计算完整文件哈希确认
- 跳过 ≤1KB 文件（`minFileSize`）

### 4.5 UnifiedScanner (actor) ★ v0.2 核心
**职责**: 统一流式扫描引擎，一次遍历替代三次全量扫描。
- `scan(rootURL:)`: 流式枚举 Home 目录 → 三路管道分流（垃圾匹配 / 大文件筛选 / 重复按大小分桶）
- 不调用 `NSEnumerator.allObjects`，每 500 文件 `autoreleasepool` + 冲刷缓冲区
- 遍历完成后对重复候选桶执行 Czkawka 三级哈希验证
- 复用 `JunkDetector.rules`（nonisolated）和 `matchesRule()`（nonisolated）做路径匹配

### 4.6 SystemMonitor (actor) ★ v0.2 新增
**职责**: 系统 CPU 与内存实时监控。
- `getCPUUsage()`: `host_processor_info()` 读取各核心 user/system/idle tick，差分计算使用率
- `getMemoryStats()`: `host_statistics64()` 获取 active + wire + speculative 页面，计算已用内存
- `snapshot()`: 返回 `SystemStats`（cpuUsage 0.0–1.0, memoryUsed, memoryTotal）
- 温度读取: 占位 (SMC 协议需后续接入 SMCKit)

### 4.7 TrashManager (actor) ★ v0.3 新增
**职责**: 应用级回收站管理，7 天保留期。
- 存储位置: `~/Documents/MacCleanerApp 回收站/`（用户可见）
- 清单文件: `.trash-manifest.json` 记录每个删除条目的元数据（ID/原路径/回收站路径/大小/删除时间/过期时间）
- `moveToTrash(_:)`: 白名单检查 → 创建 UUID 子目录 → `FileManager.moveItem` → 保存 manifest
- `restore(_:)`: `moveItem` 回原路径 → 保存 manifest → 清理空目录
- `permanentlyDelete(_:)`: `trashItem` 移入系统废纸篓 → 清理空目录 → 从 manifest 移除
- `purgeExpired()`: 每 12 小时 Timer 扫描过期条目 → 逐个 `trashItem`（清理前检查 `contentsOfDirectory` 防止误删）
- `reconcileOrphans()`: 启动时扫描回收站目录，将不在 manifest 中的孤立文件安全移入系统废纸篓（崩溃恢复）
- **安全红线**: 全流程零 `removeItem` 调用（仅对已验证为空的元数据目录使用 `removeItem`）

### 4.8 ProcessManager (actor) ★ v0.4 新增
**职责**: 进程枚举与管理。
- `runningProcesses()`: `NSWorkspace.shared.runningApplications` 枚举所有进程
- CPU 计算: `proc_pidinfo(PROC_PIDTASKINFO)` 两次采样差分（pti_total_user + pti_total_system）
- 内存: `proc_pidinfo → pti_resident_size`
- `terminateGUIApp(pid:)`: `NSRunningApplication.terminate()` → 3s timeout → `forceTerminate()`
- `nonisolated killProcess(pid:)`: `kill(SIGTERM)` → 3s → `kill(SIGKILL)`
- 系统进程白名单: Dock, WindowServer, loginwindow, SystemUIServer, Finder, mds, kernel_task, launchd

### 4.9 AppUninstaller (actor) ★ v0.4 新增
**职责**: 应用卸载与残留清理，参考 Pearcleaner 引擎。
- `scanApps()`: 扫描 `/Applications` + `~/Applications`，解析 Info.plist → Bundle ID/名称/版本
- `scanOrphans(for:)`: 在 12 个 `~/Library` 子目录搜索 Bundle ID 匹配的残留文件
- 12 个搜索路径: Application Support, Caches, Preferences, Containers, Group Containers, Logs, Saved Application State, WebKit, Cookies, HTTPStorages, LaunchAgents, Mail
- 目录大小计算使用 `autoreleasepool` + `NSEnumerator` 流式遍历
- 删除走 `TrashManager.moveToTrash()`（全流程零 `removeItem`）

## 5. UI 组件

### 5.1 AppTheme
暗色 HUD 风格主题：
- Background: `#0A0A0F`（深黑）
- Surface: `#14141F`（卡片背景）
- Accent: `#00D4AA`（青色强调）
- Sunburst Gradient: 绿→青→蓝→紫 五阶渐变色

### 5.2 RadialBarChart ★ v0.4 新增 (替代 SunburstChart)
极坐标辐射状柱状图：
- 8 根柱子均分 360°，柱高正比于文件类型总大小
- 柱内 4 段颜色深浅分层（巨型>1GB / 大100MB-1GB / 中10-100MB / 小<10MB）
- 点击柱子 → tooltip 显示分段明细
- spring 弹出动画

### 5.3 SunburstChart (DEPRECATED v0.4 — 保留不编译，被 RadialBarChart 替代)
### 5.4 OrbitalView (DEPRECATED v0.4 — Sunburst 专有旋转容器，不再需要)

### 5.4 FileRowView / SizeBadge / StatCard
可复用的文件列表行、彩色大小标签、统计卡片。

### 5.5 DynamicIslandController ★ v0.3 新增 (替代 MenuBarController)
**职责**: 灵动岛风格菜单栏显示，集成 DynamicNotchKit（MIT 许可，SPM 包）。
- **C 模式三态交互** ★ v0.1.1: 展开态（HUD CPU/RAM 可点击）→ 3s 自动收缩 → 紧凑态（刘海两侧胶囊）→ 悬停自动展开 → 移开 2s 收缩
- **RAM Top-5 面板** ★ v0.1.1: 展开态 RAM 区域 / 紧凑态 RAM 胶囊均可点击，弹出 Top-5 内存进程面板（含终止按钮，8s 自动消失）
- **常驻胶囊**: 刘海左侧 CPU% / 右侧 RAM%，2 秒刷新，颜色分级（🟢<50% 🟡<80% 🔴≥80%）
- **通知卡片**: 扫描完成 / 清理完成时弹出 `DynamicNotchInfo`
- **警告弹窗**: CPU > 80% 持续 10 秒触发警告（带防抖）
- `AppDelegate.applicationDidFinishLaunching` 调用 `start()`，`applicationWillTerminate` 调用 `stop()`
- SPM 依赖: `DynamicNotchKit`，版本锁定 `from: "1.1.0"`
- ★ v0.4: 新增 `CompactCPUView` / `CompactRAMView` 填充刘海两侧 Compact 槽位；文字颜色改为绝对色 `Color(white: 0.7/0.9)` 替代 `.secondary`/`.primary`
- 旧 `MenuBarController.swift`、`SunburstChart.swift`、`OrbitalView.swift` 已废弃（保留在磁盘上标记 DEPRECATED）

## 6. 模块视图

### 6.1 Dashboard
- 磁盘环形图（已用百分比 + 渐变色）
- "一键扫描"按钮 → 串联 Junk + LargeFile + Duplicate
- 统计卡片行（垃圾/大文件/重复组）
- 扫描图覆盖层（HUD 进度环）

### 6.2 FileClassifier
- ★ v0.4: SunburstChart → RadialBarChart，移除 Orbit 旋转变焦交互
- 独立扫描（`FileScanner.scanDirectory`）
- 底部图例

### 6.3 JunkCleaner
- 三级折叠面板（`expandedSections` 管理展开/折叠）
- 每级内按类别分组展示，显示大小和文件数，右侧 ℹ️ 按钮点击展开文件详情
- 文件详情 Sheet: 文件名/路径/大小，右键 Reveal in Finder
- 底部操作栏（已选汇总 + 预览 + 清理按钮）
- ★ v0.3: 删除分流——确认弹窗 → `trashManager.moveToTrash()` → 回收站提示 → 灵动岛通知
- 预览 Sheet / 操作日志 Sheet

### 6.4 LargeFileFinder
- 双筛选器（大小阈值 / 时间阈值）
- 文件列表（LazyVStack 性能优化）
- 右键菜单（Reveal in Finder / Quick Look）
- ★ v0.3: 删除分流——确认弹窗 → `trashManager.moveToTrash()` → 回收站提示

### 6.5 DuplicateFinder
- 重复组卡片（每组显示文件列表 + 保留最旧策略）
- "全部选中" 一键勾选所有重复项
- 统计摘要（重复组数 / 可删文件 / 可释放空间）
- ★ v0.3: 删除分流——确认弹窗 → `trashManager.moveToTrash()` → 回收站提示

### 6.6 DiskAnalyzer
- 视图模式切换（辐射图 / 柱状图 / 树图）
- 磁盘摘要卡片
- 详细分布列表
- ★ v0.3: 数据源改为 UnifiedScanner 第四路分类管道
- ★ v0.4: SunburstChart → RadialBarChart；新增 TreeMapChart 树图
- ★ v0.1.1: 整体包裹 ScrollView 支持滚动；树图高度缩减（400→280）+ 字体增大（~1/3 格宽）；放射图内圈 0.22→0.25

### 6.7 TrashBin ★ v0.3 新增
- 回收站页面（侧边栏 ♻️ 回收站入口）
- 头部: 刷新按钮 + StatCard 统计（文件总数/总大小/即将过期数）
- 空状态: 无文件时显示引导文字
- 文件列表（LazyVStack）: 文件图标（复用 `FileCategory.iconName`）、名称、原路径、大小、过期倒计时
- 操作: 🔄 恢复（`trashManager.restore()`）→ 结果弹窗 / 🗑️ 彻底删除（确认弹窗 → `trashManager.permanentlyDelete()`）→ 系统废纸篓
- 错误处理: do/catch + successCount 部分成功报告
- 每 12 小时自动清理过期条目（由 `TrashManager.start()` 的 Timer 驱动）
- ★ v0.4: 批量操作栏（恢复选中 / 彻底删除选中）

### 6.8 ProcessManager ★ v0.4 新增
- 侧边栏页面（⚡ 进程管理入口）
- 搜索栏 + 分类筛选（GUI 应用 / 后台进程 / 全部）
- 表格列: 进程名 | CPU% | 内存 | PID | 操作
- 系统进程（Dock/WindowServer 等）标记 🔒，按钮置灰
- 终止操作: GUI → `terminate()` → 3s → `forceTerminate()`；后台 → `SIGTERM` → 3s → `SIGKILL`
- 2 秒自动刷新 + StatCard 统计卡片
- 确认弹窗 → 结果提示

### 6.9 AppUninstaller ★ v0.4 新增
- 侧边栏页面（🗑️ 软件卸载入口）
- 扫描 /Applications + ~/Applications 列出已安装应用（图标 + 名称 + 版本 + 大小）
- "分析残留" → 深度扫描 12 个 ~/Library 子目录匹配 Bundle ID
- 残留清单（应用本体 + 所有残留文件，显示路径 + 大小）
- 卸载 → 确认弹窗 → `TrashManager.moveToTrash()` → 灵动岛通知
- 参考 Pearcleaner 13k★ 引擎逻辑

## 7. 并发模型

```
AppState.scanTask (全生命周期，切页不取消)
     │
     │  await
     ▼
┌────────────────┐     nonisolated      ┌──────────────┐
│ UnifiedScanner │ ←────────────────── │ JunkDetector │
│ (actor)        │    rules/matchesRule │ (actor)      │
│                │                      │              │
│ streamScan()   │  每 500 文件冲刷      │              │
│ processBatch() │  autoreleasepool     │              │
└────────────────┘                      └──────────────┘
     │
     │  @Sendable progressHandler
     ▼
┌─────────────┐
│  AppState   │  Task { @MainActor in }
│  @MainActor │  self.scanProgress = x
└─────────────┘
```

- Swift 6 严格并发检查（`Complete`）
- 所有 Service 用 `actor` 实现，外部必须 `await`
- `JunkDetector.rules` 和 `matchesRule()` 标记 `nonisolated` 供 UnifiedScanner 同步调用
- UI 更新通过 `@Sendable` 闭包回调 + `Task { @MainActor in }` 回到主线程
- AppState 持有 `scanTask: Task<Void, Never>?`，View 销毁不取消扫描

## 8. 安全模型

```
文件删除决策树 (v0.3):
┌──────────────┐
│  用户点删除   │
└──────┬───────┘
       ▼
┌──────────────┐
│  确认弹窗     │  ← 显示文件数和总大小
└──────┬───────┘
       ▼
┌──────────────┐    是     ┌──────────┐
│ isProtected? │─────────→│  跳过     │
└──────┬───────┘          └──────────┘
       │ 否
       ▼
┌──────────────┐
│ moveItem()    │  → ~/Documents/MacCleanerApp 回收站/<uuid>/
│ 应用级回收站   │     7 天保留期，用户可见可恢复
└──────┬───────┘
       ▼
┌──────────────┐
│ 提示弹窗       │  "已移入回收站，保留 7 天"
└──────┬───────┘
       │ (用户可选)
       ├─→ 🔄 恢复: moveItem 回原路径
       └─→ 🗑️ 彻底删除: trashItem → 系统废纸篓
       
       │ (7 天后自动)
       └─→ trashItem → 系统废纸篓 (仍可恢复 30 天)
```

- **白名单**: 13 个系统关键路径 + 4 种系统扩展名
- **应用回收站**: `~/Documents/MacCleanerApp 回收站/`，7 天保留 + 恢复 + 彻底删除
- **系统废纸篓**: `FileManager.trashItem(at:)`，macOS 原生 30 天可恢复
- **全流程零 `removeItem`**: 仅对已验证为空的元数据目录使用（见 TrashManager §4.7）
- **预览确认**: 删除前展示完整文件列表 + 确认弹窗
- **操作日志**: 每次操作可回溯

## 9. 扫描流程图 (v0.3)

```
用户点击「一键扫描」
       │
       ▼
┌──────────────────────────────────────────┐
│ UnifiedScanner.scan(homeDirectory)        │
│ ┌──────────────────────────────────────┐  │
│ │ 流式 NSEnumerator (不加 allObjects)    │  │
│ │ 每个文件 → autoreleasepool {          │  │
│ │   ├─ JunkRule.matchesRule(url)        │  │
│ │   ├─ SizeFilter (≥50MB 收集)          │  │
│ │   ├─ DupCollector (按大小分桶)         │  │
│ │   └─ FileCategory.from(extension) ←NEW│  │
│ │ }                                    │  │
│ │ 每 500 文件 → processBatch 冲刷       │  │
│ └──────────────────────────────────────┘  │
│ 遍历完成后:                                │
│ ├─ 大文件排序筛选 (>100MB / >180天)        │
│ ├─ 重复桶 × SHA-256 验证                  │
│ └─ categorizedFiles → DiskAnalyzer       │
└──────────────────────────────────────────┘
       │
       ▼
┌──────────────────────┐
│ 4 元组返回:            │
│ (junk, large, dup,    │
│  categorized)          │ → 仪表盘 + 磁盘分析展示
└──────────────────────┘
```

## 10. 未完成 / 待扩展

- [ ] Xcode 项目文件生成（当前仅 SPM，需 Xcode 打开）
- [ ] 定时扫描 / 自动清理
- [ ] 文件分类的改进算法（基于内容而非扩展名）
- [ ] CPU 温度读取（SMC 协议占位，需接入 SMCKit 或 powermetrics）
- [ ] 本地化（多语言支持）
- [ ] Apple Developer 代码签名（$99/年）

## 11. 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|---------|
| v0.1 | 2026-05-31 | 初始版本：6 模块 + 3 重扫描（FileScanner/JunkDetector/DuplicateDetector） |
| v0.2 | 2026-05-31 | UnifiedScanner 流式扫描 + SystemMonitor + MenuBarController；内存从 60GB → ~50MB |
| v0.3 | 2026-06-01 | UnifiedScanner 第四路分类管道（DiskAnalyzer 性能修复）；DynamicNotchKit 灵动岛替代 NSStatusBar；TrashManager 应用回收站（7 天保留 + 恢复 + 彻底删除）；全部删除操作走确认弹窗 → 回收站 → 提示流程 |
| v0.4 | 2026-06-01 | RadialBarChart 替代 SunburstChart（极坐标辐射状柱状图）；灵动岛 Compact 槽位刘海包裹 + 文字颜色修复；ProcessManager 进程管理（NSWorkspace + libproc）；AppUninstaller 软件卸载（12 路径残留扫描）；回收站批量操作；垃圾详情卡死修复（异步排序） |
| v0.1.1 | 2026-06-02 | 灵动岛 C 模式三态交互（展开→3s 收缩→紧凑，悬停展开，点击 RAM 弹出 Top-5 进程面板）；磁盘分析页 ScrollView + 树图字体增大 + 放射图内圈 0.25 |
