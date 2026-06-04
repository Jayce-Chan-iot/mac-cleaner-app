# MacCleanerApp 安全测试设计

> 上线前安全 + 误删风险验证 | 2026-06-02 | v0.1.1

## 1. 背景与目标

MacCleanerApp 是一键式 macOS 垃圾文件清理工具。上线前最大风险不是功能缺陷，而是**误删用户数据**。本设计基于 `测试项目.txt` 中的上线测试规范，聚焦 Release Gate Critical 阻断项，以安全验证为第一优先级。

### 约束

- **测试环境**: 仅当前一台 Mac（Apple Silicon，macOS 15 Sequoia）
- **项目现状**: 零单元测试，22 个 Swift 源文件（~5500 行）
- **目标产出**: 可执行 XCTest 测试脚本 + GitHub Actions CI 配置 + 测试报告

### Release Gate（出现以下任意项禁止发布）

| 级别 | 条件 |
|------|------|
| Critical | 误删用户文件、误删系统文件、删除导致应用无法启动、导致系统异常 |
| High | 崩溃率 > 1%、扫描结果错误 > 5%、删除结果错误 > 1% |

---

## 2. 测试架构

### 测试分层

| 层 | 覆盖内容 | 自动化 | 进 CI |
|----|---------|--------|-------|
| **L1: 安全核心** | SafetyManager 白名单 + TrashManager 删除→恢复→过期→崩溃恢复 全链路 | ✅ XCTest | ✅ |
| **L2: 误删防御** | JunkDetector 22 规则审查 + AppUninstaller 12 路径误删风险矩阵 | ✅ XCTest | ✅ |
| **L3: 功能正确** | DuplicateDetector 三级哈希 + UnifiedScanner 流式四路分流 | ✅ XCTest | ✅ |
| **L4: 手工验证** | 兼容性 / UI / 异常 / 性能 | ❌ 手工 | ❌ |

### 测试文件结构

```
Tests/MacCleanerAppTests/
├── SafetyManagerTests.swift        # L1: 白名单 + 删除路径正确性
├── TrashManagerTests.swift         # L1: 回收站增/删/恢复/过期/崩溃恢复
├── JunkDetectorTests.swift         # L2: 22 条规则匹配 + 误匹配检测
├── AppUninstallerTests.swift       # L2: 误删风险矩阵 12 路径审计
├── DuplicateDetectorTests.swift    # L3: 三级哈希去重正确性
├── UnifiedScannerTests.swift       # L3: 流式扫描四路分流 + 内存红线
├── TestDataFactory.swift           # 共享：测试文件创建工具
└── XCResultBundle/                 # 测试结果归档
```

### CI 配置

```yaml
# .github/workflows/safety-gate.yml
name: Safety Gate

on: [push, pull_request]

jobs:
  security-and-safety:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run Safety Tests
        run: |
          swift test --filter "SafetyManagerTests|TrashManagerTests|JunkDetectorTests|AppUninstallerTests"
  
  functional:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run Functional Tests
        run: |
          swift test --filter "DuplicateDetectorTests|UnifiedScannerTests"
```

---

## 3. L1 安全核心 — 测试用例详设

### 3.1 SafetyManagerTests

| ID | 用例 | 输入 | 断言 |
|----|------|------|------|
| S01 | test_systemPathBlocked | `/System/Library/CoreServices/Finder.app` | `isProtected == true` |
| S02 | test_userDocumentNotBlocked | `~/Documents/report.pdf` | `isProtected == false` |
| S03 | test_binSbinUsrLibBlocked | `/bin/bash`, `/sbin/launchd`, `/usr/lib/libSystem.dylib` | 全部 `isProtected == true` |
| S04 | test_trashItemCalledNotRemoveItem | 源码字符串扫描 | 不包含 `FileManager.default.removeItem`（除 TrashManager 空目录清理） |
| S05 | test_whitelistCompleteness | `SafetyManager.protectedPaths` | `count >= 13` |

### 3.2 TrashManagerTests

| ID | 用例 | Given | When | Then |
|----|------|-------|------|------|
| T01 | test_moveToTrash_createsEntry | 创建临时文件 | `trashManager.moveToTrash(url)` | 文件不在原路径，回收站 UUID 目录存在，manifest 有记录 |
| T02 | test_restore_putsFileBack | 已移入回收站 | `trashManager.restore(id)` | 文件回到原路径，manifest 无记录 |
| T03 | test_permanentlyDelete_trashItem | 已移入回收站 | `trashManager.permanentlyDelete(id)` | 回收站文件消失，manifest 无记录 |
| T04 | test_purgeExpired_autoCleanup | 手动构造过期时间=昨天的 TrashItem | `trashManager.purgeExpired()` | 过期条目被 trashItem，manifest 中移除 |
| T05 | test_reconcileOrphans_cleanup | 回收站有孤立文件（不在 manifest） | `trashManager.reconcileOrphans()` | 孤立文件安全移入系统废纸篓 |
| T06 | test_noRemoveItemCalled | 源码审查 | — | `removeItem` 仅用于已验证为空的元数据目录 |

---

## 4. L2 误删防御 — 测试用例详设

### 4.1 JunkDetectorTests

| ID | 用例 | 输入路径 | 断言 |
|----|------|---------|------|
| J01 | test_cacheRule_matches | `~/Library/Caches/com.apple.Safari/Cache.db` | 匹配 `.userCache`, safetyLevel `.safe` |
| J02 | test_logRule_matches | `~/Library/Logs/DiagnosticReports/SpinReport.spin` | 匹配 `.systemLogs`, safetyLevel `.safe` |
| J03 | test_xcodeRule_matches | `~/Library/Developer/Xcode/DerivedData/xxx.o` | 匹配 `.xcodeJunk`, safetyLevel `.caution` |
| J04 | test_userDocument_NOT_matched ★ | `~/Documents/work/presentation.key` | `matchesRule` 返回 nil |
| J05 | test_userDesktop_NOT_matched ★ | `~/Desktop/tax-2025.pdf` | `matchesRule` 返回 nil |
| J06 | test_weChatData_NOT_matched ★ | `~/Library/Containers/com.tencent.xinWeChat/...` | `matchesRule` 返回 nil |
| J07 | test_chromeProfile_NOT_matched ★ | `~/Library/Application Support/Google/Chrome/Default/History` | `matchesRule` 返回 nil |
| J08 | test_ruleCount_equals22 | — | `JunkDetector.rules.count == 22` |

### 4.2 AppUninstallerTests

| ID | 用例 | 验证内容 | 断言 |
|----|------|---------|------|
| A01 | test_searchPaths_count12 | 扫描路径数组 | 包含 12 个 `~/Library` 子目录 |
| A02 | test_scanPath_excludesUserDocuments ★ | 12 路径审查 | 不含 `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Downloads` |
| A03 | test_uninstallGoesToTrash ★ | Mock 残留文件 | 删除走 `TrashManager.moveToTrash`，不走 `removeItem` |
| A04 | test_bundleID_weChat_safe | Bundle ID `com.tencent.xinWeChat` | 残留文件列表不含聊天记录数据库 `Message/*.db` |

> ★ 标记的用例为误删风险矩阵关键用例，测试文档明确要求覆盖微信/Chrome/Xcode 等常见应用的数据目录。

---

## 5. L3 功能正确性 — 测试用例详设

### 5.1 DuplicateDetectorTests

| ID | 用例 | Given | Then |
|----|------|-------|------|
| D01 | test_identicalFiles_detected | 3 个内容相同的文件（不同名） | 1 个 DuplicateGroup，包含 3 个文件 |
| D02 | test_differentContent_notDetected | 2 个大小相同但内容不同的文件 | 无重复组 |
| D03 | test_tooSmallFiles_skipped | 2 个 < 1KB 的相同文件 | 无重复组（`minFileSize` 过滤） |
| D04 | test_level1_sizeFilter | 不同大小文件混合 | 仅大小相同进入第 2 级 |

### 5.2 UnifiedScannerTests

| ID | 用例 | Given | Then |
|----|------|-------|------|
| U01 | test_fourWaySplit | 含缓存+大文件+重复+分类的目录 | 四路结果均非空 |
| U02 | test_noAllObjects_call | 源码字符串扫描 | 不含 `.allObjects` 调用 |
| U03 | test_batchFlush_every500 | 1000+ 文件目录 | 进度回调被多次调用 |

---

## 6. L4 手工验证清单

| ID | 测试项 | 验证方法 |
|----|--------|---------|
| M1 | App 启动不崩溃 | 双击启动 |
| M2 | 扫描过程中取消 | 点击取消按钮，确认无残留扫描进程 |
| M3 | 删除确认弹窗 | 勾选文件→删除→确认弹窗显示文件数和总大小 |
| M4 | 回收站恢复 | 删除文件→回收站恢复→原路径出现 |
| M5 | 灵动岛 C 模式 | 启动 3s 收缩→悬停展开→点击 RAM 弹出面板 |
| M6 | 深色模式 | 确认暗色 HUD 主题各页面正常 |
| M7 | 窗口缩放 | 拖拽窗口四角无布局崩溃 |
| M8 | 中文/英文显示 | 各页面无乱码、无截断 |
| M9 | 磁盘不足处理 | 代码审查：catch 分支有用户提示 |

---

## 7. 误删风险测试矩阵（专项）

根据测试文档的额外要求，以下流行应用的常见数据目录必须被保护：

| App | 风险路径 | 验证方式 | 优先级 |
|-----|---------|---------|--------|
| 微信 | `~/Library/Containers/com.tencent.xinWeChat/` | JunkDetector 规则不匹配 + AppUninstaller 不误删 | P0 |
| Chrome | `~/Library/Application Support/Google/Chrome/` | JunkDetector 规则不匹配 | P0 |
| Xcode | `~/Library/Developer/Xcode/` | DericedData/Archives 匹配为垃圾（正确），UserData 不匹配（保护） | P0 |
| VS Code | `~/.vscode/`, `~/Library/Application Support/Code/` | JunkDetector 规则不匹配用户配置 | P0 |
| Docker | `~/Library/Containers/com.docker.docker/` | 不被识别为可清理垃圾 | P0 |
| Photos | `~/Pictures/Photos Library.photoslibrary/` | 不被识别为垃圾，不被默认勾选 | P0 |
| Final Cut Pro | `~/Movies/` | 不被识别为垃圾 | P1 |

---

## 8. 限制与已知缺口

以下项目在当前单机环境下**无法物理验证**，通过代码审查 + 逻辑推导覆盖：

| 测试项 | 限制原因 | 替代方案 |
|--------|---------|---------|
| macOS 13 Ventura 兼容性 | 无对应版本机器 | 审查 API 使用（最低 macOS 14 声明） |
| macOS 14 Sonoma 兼容性 | 当前运行 macOS 15 | 审查 SwiftUI API（未用 v15+ 专有 API） |
| Intel Mac 兼容性 | 仅 Apple Silicon | Universal Binary 构建验证（lipo 合并成功即通过） |
| 100 万文件扫描 | 无测试数据 | 代码审查：流式批处理逻辑 + `autoreleasepool` 模式 |
| 24 小时长稳 | 时间成本 | 代码审查：Timer/NotificationCenter 正确释放 |
| 外接 4K 显示器 | 无设备 | SwiftUI Layout 自适应（理论兼容） |

---

## 9. 测试执行顺序

```
Phase 1: 环境准备
  ├── 创建 Tests/MacCleanerAppTests/ 目录
  ├── 添加 Package.swift testTarget
  └── 创建 TestDataFactory.swift

Phase 2: L1 安全核心（最关键，先跑通）
  ├── SafetyManagerTests.swift
  └── TrashManagerTests.swift

Phase 3: L2 误删防御
  ├── JunkDetectorTests.swift
  └── AppUninstallerTests.swift

Phase 4: L3 功能正确
  ├── DuplicateDetectorTests.swift
  └── UnifiedScannerTests.swift

Phase 5: CI 配置
  └── .github/workflows/safety-gate.yml

Phase 6: L4 手工验证
  └── 9 项手工检查 → 测试报告
```
