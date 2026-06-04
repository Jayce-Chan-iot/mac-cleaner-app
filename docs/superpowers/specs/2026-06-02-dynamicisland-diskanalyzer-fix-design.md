# Dynamic Island 交互修复 + 磁盘分析页面优化 — 设计文档

> 日期：2026-06-02 | 版本：v0.1.1

## 背景

v0.4.0 实现了灵动岛 D 模式（点击 RAM 弹出 Top-5 进程）和磁盘分析页面（辐射图 + 柱状图 + 树状图），但存在两个问题。

---

## 问题 1：灵动岛点击无反应

### 根因

`DynamicIslandController.start()` 调用 `expand()` 后永远不收缩。`CompactRAMView`（含 Button）仅在紧凑态渲染，用户永远看不到点击目标。同时 `NotchHUDView` 展开态的 RAM 区域没有点击事件。

### 设计：C 模式（三态交互）

三态：展开态 → 紧凑态 → 悬停展开，全部可点击 RAM 弹出 Top-5。

```
展开态 (0-3s) ──3s──→ 紧凑态 ←──悬停/移开──→ 悬停展开
    │                    │                       │
    └──── 点击 RAM ──────┴───────────────────────┘
                         ↓
                   Top-5 面板 (8s 自动消失)
```

### 改动点

| 文件 | 改动 |
|------|------|
| `DynamicIslandController.swift` — `NotchHUDView` | RAM 区域包裹 `Button`，点击发 `showRAMProcessPanel` 通知 |
| `DynamicIslandController.swift` — `start()` | `expand()` → 等 3s → `compact()` |
| `DynamicIslandController.swift` — 新增悬停逻辑 | 监听 `isHovering`，悬停 `expand()`，移开 2s 后 `compact()` |
| `DynamicIslandController.swift` — `toggleRAMPanel()` | 保持不变，已正确实现 |

### NotchHUDView RAM 区域改动

```swift
// 原来：纯展示
HStack(spacing: 4) {
    Circle().fill(ramColor).frame(width: 6, height: 6)
    Text("RAM").font(...).foregroundColor(...)
    Text("\(data.ramPercent)%").font(...).foregroundColor(.white)
}

// 改为：包裹 Button
Button {
    NotificationCenter.default.post(name: .showRAMProcessPanel, object: nil)
} label: {
    HStack(spacing: 4) {
        Circle().fill(ramColor).frame(width: 6, height: 6)
        Text("RAM").font(...).foregroundColor(...)
        Text("\(data.ramPercent)%").font(...).foregroundColor(.white)
    }
}
.buttonStyle(.plain)
```

---

## 问题 2：磁盘分析页面显示不全

### 根因

`DiskAnalyzerView` body 是普通 `VStack`，无 ScrollView。树状图 frame 400pt 过大挤占空间，字体公式 `min(width/10, 13)` 在窄格中字体极小。放射图内圈 0.22×maxRadius 偏小。

### 改动点

| 文件 | 改动 |
|------|------|
| `DiskAnalyzerView.swift` | body 最外层包裹 `ScrollView(.vertical, showsIndicators: true)` |
| `DiskAnalyzerView.swift` — TreeMap frame | `height: 400` → `height: 280` |
| `TreeMapChart.swift` — 标签字体 | `min(rect.width / 10, 13)` → `min(rect.width / 3.5, 14)` |
| `TreeMapChart.swift` — 大小字体 | `min(rect.width / 14, 10)` → `min(rect.width / 4.5, 11)` |
| `RadialBarChart.swift` — 内圈半径 | `maxRadius * 0.22` → `maxRadius * 0.25` |

### 字体公式说明

目标：标签字体约占格子宽度的 1/3。格子宽度通常在 80-200px 范围。
- 标签：`min(rect.width / 3.5, 14)` — 80px 格 → 22pt（cap 14pt），120px → 34pt（cap 14pt）
- 大小：`min(rect.width / 4.5, 11)` — 80px 格 → 17pt（cap 11pt），120px → 26pt（cap 11pt）

---

## 不改动的部分

- `ProcessManager` / `AppUninstaller` / `TrashManager` — 不涉及
- `RadialBarChart` 动画、tooltip、颜色 — 不变
- `TreeMapChart` 布局算法、下钻、颜色 — 不变
- `DynamicNotchKit` 本身 — 不修改库代码
- `RAMTopProcessView` — 面板内容不变
