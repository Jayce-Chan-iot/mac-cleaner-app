# MacCleanerApp 手工验证清单

> 版本: v0.1.1 | 日期: ________ | 测试人: ________

## L4 手工验证

| ID | 测试项 | 方法 | 结果 | 备注 |
|----|--------|------|------|------|
| M1 | App 启动不崩溃 | 双击启动 | ☐ 通过 ☐ 失败 | |
| M2 | 扫描可取消 | 点击取消按钮 | ☐ 通过 ☐ 失败 | |
| M3 | 删除确认弹窗 | 勾选文件→删除→验证弹窗内容 | ☐ 通过 ☐ 失败 | |
| M4 | 回收站恢复 | 删除→回收站→恢复→验证 | ☐ 通过 ☐ 失败 | |
| M5 | 灵动岛 C 模式 | 启动→3s收缩→悬停展开→点击RAM | ☐ 通过 ☐ 失败 | |
| M6 | 暗色模式 | 检查所有页面 | ☐ 通过 ☐ 失败 | |
| M7 | 窗口缩放 | 拖拽四角无布局崩溃 | ☐ 通过 ☐ 失败 | |
| M8 | 中文显示 | 检查无乱码无截断 | ☐ 通过 ☐ 失败 | |
| M9 | 磁盘不足提示 | 代码审查catch分支 | ☐ 通过 ☐ 失败 | |

## 误删风险矩阵

| App | 风险路径 | 扫描误匹配 | 卸载误删 | 结果 |
|-----|---------|:---:|:---:|------|
| 微信 | ~/Library/Containers/com.tencent.xinWeChat/ | ☐ 否 ☐ 是 | ☐ 否 ☐ 是 | |
| Chrome | ~/Library/Application Support/Google/Chrome/ | ☐ 否 ☐ 是 | — | |
| Xcode | ~/Library/Developer/Xcode/ | ☐ 否 ☐ 是 | — | |
| VS Code | ~/Library/Application Support/Code/ | ☐ 否 ☐ 是 | — | |
| Docker | ~/Library/Containers/com.docker.docker/ | ☐ 否 ☐ 是 | — | |
| Photos | ~/Pictures/Photos Library.photoslibrary/ | ☐ 否 ☐ 是 | — | |
| Final Cut Pro | ~/Movies/ | ☐ 否 ☐ 是 | — | |

## 已知问题

| 文件 | 问题 | 严重度 |
|------|------|--------|
| JunkDetector.swift:194 | enumerateJunkFiles 使用 .allObjects | Medium |
| DuplicateDetector.swift:87 | collectFiles 使用 .allObjects | Medium |

## Release Gate 判定

| 阻断条件 | 触发 | 说明 |
|---------|:---:|------|
| 误删用户文件 | ☐ | |
| 误删系统文件 | ☐ | |
| 删除导致应用无法启动 | ☐ | |
| 导致系统异常 | ☐ | |
| 崩溃率 > 1% | ☐ | |
| 扫描结果错误 > 5% | ☐ | |
| 删除结果错误 > 1% | ☐ | |

**最终判定: ☐ 可发布  ☐ 需修复  ☐ 需更多测试**
