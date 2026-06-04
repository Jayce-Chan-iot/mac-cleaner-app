# Mac 清理助手

> macOS 原生文件分类整理 + 垃圾文件清理工具 | Swift 6 · SwiftUI · macOS 14+

[![Swift](https://img.shields.io/badge/Swift-6.3-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-Non--Commercial-red)](LICENSE)

---

## 目录

- [功能一览](#功能一览)
- [界面预览](#界面预览)
- [安全设计](#安全设计)
- [项目架构](#项目架构)
- [代码原理](#代码原理)
- [开源参考](#开源参考)
- [编译与运行](#编译与运行)
- [签名问题解决](#签名问题解决)
- [许可证](#许可证)

---

## 功能一览

### 🏠 仪表盘
磁盘总览（总量 / 已用 / 可用）+ 环形进度图。"一键扫描"按钮串联垃圾清理、大文件查找、重复检测和文件分类，一次遍历四路分流，< 2 分钟完成全盘扫描。底部展示扫描结果统计卡片。

### 📁 文件分类
**辐射状柱状图**（RadialBarChart）—— 8 根柱按文件类型均分 360°，柱内 4 段颜色深浅分层（巨型 >1GB / 大 100MB-1GB / 中 10-100MB / 小 <10MB）。点击柱子展开分段明细 tooltip，spring 弹出动画。底部图例标识文件类型。

### 🗑️ 垃圾清理
三级安全折叠面板，12 类垃圾按风险分级：
- 🟢 **可安全清理**：系统缓存、应用缓存、浏览器缓存、日志、废纸篓
- 🟡 **建议检查**：Xcode 垃圾、邮件附件、DMG 安装包、旧 iOS 备份
- 🔴 **需专家检查**：Homebrew 缓存、Docker 残留、npm/Cargo 缓存

点击 ℹ️ 查看详细文件列表，删除走确认弹窗 → 应用回收站（7 天可恢复）。

### 📦 大文件查找
按大小（默认 >100MB）和时间（默认 6 个月未访问）双筛选。列表按大小降序，显示图标、名称、路径、末次访问时间。右键 Reveal in Finder / Quick Look。删除走回收站。

### 🔍 重复文件检测
**Czkawka 三级哈希过滤算法**——第 1 级按文件大小分组，第 2 级计算前 4KB SHA-256 哈希，第 3 级完整文件哈希确认。结果按组展示，默认保留最旧文件、勾选重复项。删除走回收站。

### 📊 磁盘分析
三种可视化模式任意切换：**辐射图**（8 柱分层） / **柱状图**（Swift Charts SectorMark） / **树图**（squarified 布局）。流畅滚动，流式数据源零内存泄漏。点击区块 drill-down 查看详情。

### ♻️ 回收站
应用级回收站（`~/文稿/MacCleanerApp 回收站/`），7 天保留期，支持**恢复**和**彻底删除**。每 12 小时自动清理过期条目。启动时崩溃恢复扫描孤立文件。批量操作栏（恢复选中 / 彻底删除选中）。

### 🏝️ 灵动岛菜单栏
**C 模式三态交互**——展开 HUD（CPU/RAM 实时数据，RAM 区域可点击）→ 3 秒自动收缩 → 刘海两侧胶囊（CPU% / RAM%，颜色分级 🟢<50% 🟡<80% 🔴≥80%）→ 鼠标悬停自动展开 → 移开 2 秒后收缩。2 秒刷新一次。点击 RAM 弹出 **Top-5 内存进程面板**（含终止按钮，8 秒自动消失）。扫描 / 清理完成时弹出通知卡片。

### ⚡ 进程管理
类似任务管理器，查看所有运行进程（名称 / CPU% / 内存 / PID）。搜索栏 + 分类筛选（GUI 应用 / 后台进程 / 全部）。系统进程（Dock、WindowServer、Finder 等）标记 🔒 禁止终止。GUI 应用走 `NSRunningApplication.terminate()`，后台进程走 `SIGTERM → 3s → SIGKILL` 两级终止。2 秒自动刷新。

### 🗑️ 软件卸载
扫描 `/Applications` + `~/Applications` 列出已安装应用（图标 + 名称 + 版本 + 大小）。"分析残留"功能深度扫描 **12 个系统目录**（Application Support、Caches、Preferences、Containers、Group Containers、Logs、Saved Application State、WebKit、Cookies、HTTPStorages、LaunchAgents、Mail）匹配 Bundle ID。卸载走确认弹窗 → 回收站。

### 🔒 轻量运行
运行时内存 **~100MB**（目标 <200MB）。流式扫描 + `autoreleasepool` + 每 500 文件冲刷缓冲区，禁止一次性物化全量文件列表。

---

## 界面预览

| 设计维度 | 说明 |
|---------|------|
| **主题** | 暗色 HUD 科技风格 |
| **主背景** | `#0A0A0F` 深黑 |
| **卡片背景** | `#14141F` 半透明深色 + 1px `#2A2A3C` 边框 |
| **强调色** | `#00D4AA` 青色（数据指标、进度环、按钮高亮） |
| **图表渐变** | 绿 → 青 → 蓝 → 紫 五阶科技渐变色 |
| **布局** | `NavigationSplitView` 三栏：侧边栏模块选择 + 中间详情 + 右侧工具面板 |
| **字体** | 系统圆体 `.rounded`（标题 28pt/20pt）+ 等宽数码 `.monospaced`（36pt 数值） |
| **卡片** | 12pt 圆角 + 可选渐变边框（青色 → 深色） |
| **灵动岛** | DynamicNotchKit C 模式——刘海集成 CPU/RAM 胶囊，悬停展开 HUD，点击弹出进程面板 |

### 自定义图表组件

**RadialBarChart**（极坐标辐射状柱状图）：8 根柱均分 360°，柱高正比于文件类型总大小，柱内 4 段颜色分层（巨型 / 大 / 中 / 小），点击展开 tooltip，spring 动画。内圈半径 25% 留白区域。

**TreeMapChart**（squarified 矩阵树图）：按文件类型递归切分矩形区域，面积正比于大小。字体自适应（字形 ~1/3 格宽，上限 14pt）。用于磁盘分析模块的第三种可视化模式。

---

## 安全设计

### 删除全流程零 `removeItem`

```
用户点击删除
    │
    ▼
确认弹窗（显示文件数和总大小）
    │
    ▼
白名单检查 ──是──→ 跳过（/System、/bin、/sbin 等 13 个系统路径）
    │ 否
    ▼
moveItem → ~/文稿/MacCleanerApp 回收站/<uuid>/（7 天保留，用户可见可恢复）
    │
    ├──→ 🔄 恢复（moveItem 回原路径）
    └──→ 🗑️ 彻底删除（trashItem → 系统废纸篓，macOS 原生 30 天可恢复）
         │
         │ 7 天后自动
         └──→ trashItem → 系统废纸篓
```

### 保护措施一览

| 措施 | 说明 |
|------|------|
| **白名单保护** | 13 个系统关键路径硬编码排除（`/System`、`/bin`、`/sbin`、`/usr/lib`、`/usr/bin` 等） + 4 种系统扩展名 |
| **二级回收站** | 应用级（7 天可恢复）→ 系统废纸篓（30 天可恢复），全程零 `removeItem` |
| **预览确认** | 删除前展示完整文件列表 + 总大小 + 确认弹窗 |
| **操作日志** | 每次删除记录时间、文件列表、释放空间，可回溯查看 |
| **崩溃恢复** | 启动时自动扫描回收站目录，将不在清单中的孤立文件安全移入系统废纸篓 |
| **系统进程保护** | Docker、WindowServer、loginwindow、Finder、kernel_task 等 8 个系统进程禁止终止 |

---

## 项目架构

```
Sources/MacCleanerApp/
├── App/                         # @main 入口 + NavigationSplitView 三栏布局
│   ├── MacCleanerApp.swift      # AppState（@MainActor）+ 9 个 Module 枚举
│   └── ContentView.swift        # 侧边栏 + 模块路由
├── Models/                      # 数据模型（纯 struct/enum，全部 Sendable）
│   ├── FileItem.swift           # 文件条目 + FileCategory 枚举（8 大文件类型 + 扩展名映射）
│   ├── ScanResult.swift         # 扫描结果聚合 + DuplicateGroup + DiskInfo
│   ├── JunkCategory.swift       # 12 类垃圾 + SafetyLevel（safe/caution/expert）
│   ├── TrashItem.swift          # 回收站条目（Codable, Identifiable, Sendable）
│   └── InstalledApp.swift       # 已安装应用（Bundle ID + 版本 + 残留文件列表）
├── Services/                    # 核心引擎（全部 actor 实现，Swift 6 并发安全）
│   ├── UnifiedScanner.swift     # ★ 统一流式扫描（一次遍历四路分流）
│   ├── SafetyManager.swift      # 白名单检查 + 回收站删除 + 操作日志
│   ├── JunkDetector.swift       # 22 条内置扫描规则 + Glob 模式匹配
│   ├── DuplicateDetector.swift  # 三级哈希过滤（大小→前置→全文件 SHA-256）
│   ├── FileScanner.swift        # 磁盘信息获取
│   ├── SystemMonitor.swift      # CPU/内存实时监控（host_processor_info + host_statistics64）
│   ├── TrashManager.swift       # 应用回收站（7 天保留 + 恢复 + 定时清理 + 崩溃恢复）
│   ├── ProcessManager.swift     # 进程管理（NSWorkspace + libproc + SIGTERM/SIGKILL）
│   └── AppUninstaller.swift     # 软件卸载（12 路径 Bundle ID 残留扫描）
├── UI/
│   ├── Theme/
│   │   ├── AppTheme.swift       # 颜色体系（Hex → Color extension）+ 字体 + 卡片样式
│   │   └── ColorPalette.swift   # 文件类别 → 颜色映射
│   └── Components/
│       ├── DynamicIslandController.swift  # 灵动岛控制器（C 模式三态交互 + Top-5 面板）
│       ├── RadialBarChart.swift           # 极坐标辐射状柱状图（8 柱 4 段分层）
│       ├── TreeMapChart.swift             # squarified 矩阵树图
│       └── FileRowView.swift              # 文件行视图（图标 + 名称 + 路径 + 大小）
└── Modules/                     # 9 个功能模块视图
    ├── Dashboard/               # 仪表盘（磁盘环形图 + 一键扫描）
    ├── FileClassifier/          # 文件分类（RadialBarChart 辐射图）
    ├── JunkCleaner/             # 垃圾清理（三级折叠面板）
    ├── LargeFileFinder/         # 大文件查找（大小/时间双筛选）
    ├── DuplicateFinder/         # 重复检测（分组卡片）
    ├── DiskAnalyzer/            # 磁盘分析（辐射图/柱状图/树图三模式 + ScrollView）
    ├── TrashBin/                # 回收站（文件列表 + 倒计时 + 批量恢复/删除）
    ├── ProcessManager/          # 进程管理（搜索 + 筛选 + 终止）
    └── AppUninstaller/          # 软件卸载（残留分析 + 确认弹窗）
```

### 技术栈

| 维度 | 选择 |
|------|------|
| 语言 | Swift 6（严格并发检查 `Complete`） |
| UI 框架 | SwiftUI（macOS 14+） |
| 架构模式 | MVVM，单体多模块 |
| 图表 | Swift Charts（SectorMark） + 自研 RadialBarChart / TreeMapChart |
| 并发模型 | Swift Concurrency（actor、TaskGroup、@MainActor） |
| 加密哈希 | CryptoKit SHA-256（重复检测） |
| 包管理 | Swift Package Manager |
| 外部依赖 | DynamicNotchKit v1.1.0（灵动岛，MIT 许可） |

---

## 代码原理

### 统一流式扫描（UnifiedScanner）

v0.1 中三次独立全量遍历 Home 目录（垃圾检测 / 大文件查找 / 重复检测）导致 10 分钟+ 扫描时间、~60GB 峰值内存。v0.2 起改用 `UnifiedScanner` 流式一次遍历四路分流：

```
NSEnumerator 流式遍历 Home 目录（不调用 .allObjects）
     │
     │ 每个文件进入 autoreleasepool {
     ▼
    ├─→ JunkDetector.matchesRule(url)    → 垃圾收集
    ├─→ SizeFilter (≥50MB)               → 大文件候选
    ├─→ 按文件大小分桶                    → 重复候选
    └─→ FileCategory.from(extension)      → 分类统计
     }
     │
     │ 每 500 个文件 → processBatch 冲刷缓冲区，释放 AutoreleasePool
     ▼
遍历完成后：
    ├─ 大文件排序筛选（>100MB / >180 天）
    └─ 重复桶 × SHA-256 三级哈希验证
```

关键优化：
- `NSEnumerator` 流式 `for-in`，绝不调用 `.allObjects`（一次性物化是内存炸弹）
- 每 500 个文件 `autoreleasepool` + 冲刷缓冲区
- `UnifiedScanner` 用 `actor` 实现，外部 `await` 调用，内部状态隔离
- `JunkDetector.rules` 和 `matchesRule()` 标记 `nonisolated` 供同步调用

### 三级哈希去重（Czkawka 算法）

借鉴 Rust 项目 Czkawka（31k★）的算法，经 Swift 移植：

1. **第 1 级 — 大小过滤**：按文件大小分组，过滤只有 1 个文件的组（大小相同的文件可能有很多）
2. **第 2 级 — 前置哈希**：同大小组内，计算每个文件前 4KB 的 SHA-256。不同内容的文件前缀哈希不同，快速排除，避免完整哈希开销
3. **第 3 级 — 全文件验证**：前缀哈希匹配的文件组，计算完整文件 SHA-256 确认

跳过 ≤1KB 的文件（`minFileSize`），使用 CryptoKit 硬件加速。

### 二级回收站

```
应用回收站（~/文稿/MacCleanerApp 回收站/）
    ├── .trash-manifest.json        # 清单文件（ID/原路径/回收站路径/大小/删除时间/过期时间）
    └── <uuid>/                     # 每个删除操作一个 UUID 子目录
        └── 被删除的文件...

删除：moveItem → UUID 目录 → 记录 manifest
恢复：moveItem 回原路径 → 从 manifest 移除
彻底删除：trashItem → 系统废纸篓 → 从 manifest 移除
自动清理：每 12 小时扫描过期条目 → 自动 trashItem
崩溃恢复：启动扫描目录 → 孤立文件（不在 manifest 中）→ 安全移入系统废纸篓
```

### 并发模型

```
AppState.scanTask (Task, 全生命周期持有，切页不取消)
     │
     │  await
     ▼
┌────────────────┐     nonisolated rules
│ UnifiedScanner │ ←─────────────────── JunkDetector
│ (actor)        │    matchesRule()
│                │
│ streamScan()   │  每 500 文件冲刷
│ processBatch() │  autoreleasepool
└───────┬────────┘
        │
        │  @Sendable progressHandler
        ▼
┌─────────────┐
│  AppState   │  Task { @MainActor in }
│  @MainActor │  self.scanProgress = x
└─────────────┘
```

- 所有 Service 用 `actor` 实现，外部必须 `await`，编译器保证无 data race
- 进度回调标记 `@Sendable`，UI 更新通过 `Task { @MainActor in }` 回到主线程
- `AppState` 持有 `scanTask: Task<Void, Never>?`，View 销毁不取消扫描

### 动态灵动岛（C 模式三态交互）

基于 DynamicNotchKit（MIT 许可），实现刘海区域的展开-收缩-悬停交互：

```
启动 → expand (HUD)
     │
     │ 3s 后
     ▼
compact (刘海两侧胶囊)
     │
     │ isHovering == true
     ▼
expand (HUD，RAM 区域可点击)
     │
     │ 鼠标移开 + 2s
     ▼
compact
```

- hover 检测：`while` 循环轮询 DynamicNotchKit 的 `isHovering` 公开属性
- `expand()` / `compact()` 方法内部有 guard——已处于目标状态时 no-op，所以无需知道当前状态即可安全调用
- 展开态 RAM 区域包裹 `Button` + `.buttonStyle(.plain)`，点击发通知弹出进程面板
- Timer 用 `RunLoop.main.add(timer, forMode: .common)` 防止 UI tracking 时暂停

---

## 开源参考

本项目的设计大量参考了以下 GitHub 开源项目，特此致谢：

| 项目 | Stars | 语言 | 参考内容 |
|------|-------|------|---------|
| [Czkawka](https://github.com/qarmin/czkawka) | 31k | Rust | 三级哈希重复文件检测算法（大小→前置 SHA-256→全文件哈希） |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | 13k | SwiftUI | 应用卸载（Bundle ID 残留扫描） + GCD 并发扫描架构 |
| [PureMac](https://github.com/momenbasel/PureMac) | 4.4k | SwiftUI | CleanMyMac 替代品——垃圾路径规则、分类逻辑、仪表盘设计 |
| [DodoTidy](https://github.com/DodoApps/dodotidy) | 174 | SwiftUI | 磁盘可视化图表（原版 SunburstChart 基于 Swift Charts SectorMark） |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | 182 | SwiftUI | 灵动岛风格菜单栏组件（MIT 许可，SPM 包，本项目唯一外部依赖） |
| [MacSift](https://github.com/Lcharvol/MacSift) | 9 | SwiftUI | 按 App 分组扫描模式 |

### 自研组件

以下组件为本项目独立研发，未使用第三方库：

| 组件 | 说明 |
|------|------|
| **UnifiedScanner** | 流式一次遍历四路分流引擎（Czkawka 三级哈希 + PureMac 规则 + 批处理释放） |
| **RadialBarChart** | 极坐标辐射状柱状图（替代 DodoTidy SectorMark SunburstChart） |
| **TreeMapChart** | squarified 矩阵树图算法 |
| **TrashManager** | 二级回收站 + manifest 清单 + 崩溃恢复 |
| **ProcessManager** | NSWorkspace + libproc `proc_pidinfo` 差分 CPU 计算 |
| **DynamicIslandController** | DynamicNotchKit C 模式三态交互封装 |
| **SystemMonitor** | IOKit `host_processor_info` + `host_statistics64` 实时监控 |

---

## 编译与运行

### 前置条件

| 需求 | 说明 |
|------|------|
| macOS 14.0+ | Sonoma 或更高版本 |
| Xcode 16+ | 提供 macOS SDK、SwiftUI 宏插件和代码签名工具链 |
| Swift 6.0 工具链 | Xcode 自带，无需单独安装 |

### 方式一：Xcode 运行（推荐）

```bash
# 1. 克隆项目
git clone <repo-url>
cd mac垃圾文件清理助手

# 2. 解析依赖（DynamicNotchKit）
swift package resolve

# 3. 生成 Xcode 项目
swift package generate-xcodeproj

# 4. 打开项目
open MacCleanerApp.xcodeproj

# 5. 在 Xcode 中按 Cmd+R 运行
#    （首次运行需在 Signing & Capabilities 中选择 Team）
```

### 方式二：命令行编译

```bash
# 编译（不需要 Xcode，但需要 Xcode 命令行工具）
swift build

# 运行 GUI 应用需要 Xcode.app 提供 macOS SDK
swift run
```

> ⚠️ **注意**：如果未安装 Xcode（只有 Command Line Tools），`swift run` 无法启动 GUI 窗口。请用方式一或方式三。

### 方式三：打包 DMG 安装

```bash
# 一键构建 .app + .dmg（Universal Binary）
bash scripts/build-dmg.sh

# 输出：MacCleanerApp-v0.1.1.dmg
# 双击挂载 → 拖到「应用程序」文件夹即可
```

构建脚本自动完成：
1. Swift 编译（arm64 + x86_64 → lipo 合并 Universal Binary）
2. 修复 DynamicNotchKit 宏兼容性（`@Entry` → `EnvironmentKey` 手动实现）
3. 创建 `.app` Bundle 结构 + Info.plist
4. Ad-hoc 签名（`codesign --force --deep --sign -`）
5. `hdiutil` 打包 DMG（zlib level 9 压缩）

---

## 签名问题解决

### 问题：打开 App 提示「无法验证开发者」

这是 macOS Gatekeeper 的安全策略——未经过 Apple Developer 签名的应用默认被阻止。本项目的 DMG 使用 **Ad-hoc 签名**（非开发者证书），属于"未认证开发者"类别。

#### 解决方法 1：右键打开（最简单，一次性）

1. 在 Finder 中找到 `Mac 清理助手.app`
2. **右键点击** App 图标 → 选择「打开」
3. 弹出对话框点击「打开」即可

> 此方法只需操作一次，之后可直接双击打开。

#### 解决方法 2：移除隔离标记

```bash
# 如果从网络下载的 DMG，文件可能被标记 quarantine
xattr -d com.apple.quarantine /Applications/Mac\ 清理助手.app
```

#### 解决方法 3：允许任何来源（仅限 macOS 14 及以下）

```bash
# 开启"允许任何来源"选项
sudo spctl --master-disable

# 在 系统设置 → 隐私与安全性 → 安全性 中选择「任何来源」
```

> ⚠️ 不推荐长期保持此设置，安装后建议恢复：`sudo spctl --master-enable`

#### 解决方法 4：自行签名（有 Apple Developer 账号）

如果你有 Apple Developer Program 账号（$99/年），可以用自己的证书签名：

```bash
# 查看本地签名证书
security find-identity -v -p codesigning

# 用自己的证书重新签名
codesign --force --deep --sign "Your Developer ID Application: Name (TEAMID)" \
    /Applications/Mac\ 清理助手.app

# 验证签名
codesign --verify --verbose /Applications/Mac\ 清理助手.app

# 创建签名后的 DMG
hdiutil create -volname "Mac 清理助手" \
    -srcfolder /Applications/Mac\ 清理助手.app \
    -ov -format UDZO MacCleanerApp-v0.1.1-signed.dmg

# 公证（Apple 服务器验证，需要 Xcode 13+）
xcrun notarytool submit MacCleanerApp-v0.1.1-signed.dmg \
    --apple-id "your@email.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait
```

#### 签名相关问题的本质

| 签名类型 | Gatekeeper 行为 | 适用场景 |
|---------|----------------|---------|
| **无签名** | 阻止运行，系统设置无"打开"按钮 | 仅开发调试可用 |
| **Ad-hoc 签名**（本项目默认） | 警告"无法验证开发者"，但右键可打开 | 个人使用、内部分发 |
| **Apple Developer 签名** | 首次弹窗确认，后续正常 | 公开发布 |
| **Developer ID + 公证** | 无警告，直接打开 | App Store 外正式分发 |
| **App Store 分发** | 沙盒化，无任何警告 | Mac App Store |

> 本项目默认使用 Ad-hoc 签名，普通用户**右键打开**即可正常使用。

---

## 许可证

本项目采用自定义非商业源码可见许可，详见 [LICENSE](LICENSE)。

允许个人学习、研究、内部评估和非商业使用。未经版权持有人书面授权，禁止任何商业使用，包括但不限于售卖、转售、商业分发、集成到付费产品或服务、用于付费清理/维护服务、SaaS 或商业咨询交付。

本项目不是 MIT 开源项目；所有未明确授予的权利均由版权持有人保留。

本项目引用的第三方库：
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — MIT License，通过 SPM 集成

第三方许可说明见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

---

## 更多文档

| 文档 | 内容 |
|------|------|
| [CLAUDE.md](CLAUDE.md) | AI 开发规则手册（项目结构、技术约束、命名约定） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 完整架构设计（数据流、安全模型、版本历史） |

---

*Built with Swift 6 and SwiftUI. Designed for normal users. Safety first.*
