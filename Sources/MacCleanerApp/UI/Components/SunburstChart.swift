// DEPRECATED in v0.4 — replaced by RadialBarChart.swift
import SwiftUI

/// Sunburst 旭日图 —— 内圈类型 → 中圈大小 → 外圈来源
/// 支持点击下钻和轨道旋转交互
struct SunburstChart: View {
    let data: SunburstData
    @State private var rotation: Angle = .zero
    @State private var lastDragValue: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var selectedSegment: SunburstSegment?

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // 背景辉光
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.accent.opacity(0.1), .clear],
                            center: .center,
                            startRadius: size * 0.1,
                            endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)

                // 轨道环
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            AppTheme.border.opacity(0.3),
                            lineWidth: 0.5
                        )
                        .frame(
                            width: size * (0.35 + CGFloat(i) * 0.2),
                            height: size * (0.35 + CGFloat(i) * 0.2)
                        )
                }

                // 内圈：文件类型
                ForEach(data.innerRing) { segment in
                    SunburstArc(
                        segment: segment,
                        radius: (size * 0.15, size * 0.35),
                        center: center
                    )
                    .fill(ColorPalette.color(for: segment.category))
                    .opacity(selectedSegment == nil || selectedSegment?.id == segment.id ? 1.0 : 0.3)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedSegment = selectedSegment == segment ? nil : segment
                        }
                    }
                }

                // 中圈：大小细分
                if let selected = selectedSegment {
                    ForEach(selected.children) { segment in
                        SunburstArc(
                            segment: segment,
                            radius: (size * 0.37, size * 0.55),
                            center: center
                        )
                        .fill(ColorPalette.color(forFileSize: segment.size))
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // 外圈：具体来源
                if let selected = selectedSegment {
                    ForEach(selected.children.flatMap { $0.children }) { segment in
                        SunburstArc(
                            segment: segment,
                            radius: (size * 0.57, size * 0.72),
                            center: center
                        )
                        .fill(ColorPalette.color(forFileSize: segment.size).opacity(0.7))
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // 中心标签
                VStack(spacing: 2) {
                    if let selected = selectedSegment {
                        Text(selected.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(selected.formattedSize)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(AppTheme.textSecondary)
                    } else {
                        Text("文件分类")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(data.formattedTotalSize)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(AppTheme.accent)
                    }
                }
                .frame(width: size * 0.25)
            }
            .rotationEffect(rotation)
            .scaleEffect(scale)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation.width - lastDragValue
                        rotation += .degrees(delta * 0.3)
                        lastDragValue = value.translation.width
                    }
                    .onEnded { _ in
                        lastDragValue = 0
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(0.5, min(2.0, value))
                    }
            )
            .position(center)
        }
    }

    init(data: SunburstData) {
        self.data = data
    }
}

// MARK: - Sunburst Data Model

struct SunburstData {
    var innerRing: [SunburstSegment]
    let totalSize: Int64

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct SunburstSegment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let category: FileItem.FileCategory
    let label: String
    let size: Int64
    let fileCount: Int
    var children: [SunburstSegment]
    /// 预计算的起始角度（由 SunburstData.build 分配，避免渲染时 UUID hash 重算）
    var startAngle: Angle = .zero

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var percentage: Double {
        guard totalGroupSize > 0 else { return 0 }
        return Double(size) / Double(totalGroupSize)
    }

    /// 计算父组总大小（用于百分比计算）
    fileprivate var totalGroupSize: Int64 {
        if children.isEmpty {
            return size
        }
        return children.reduce(0) { $0 + $1.size }
    }

    static func == (lhs: SunburstSegment, rhs: SunburstSegment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sunburst Arc Shape

struct SunburstArc: Shape {
    let segment: SunburstSegment
    let radius: (inner: CGFloat, outer: CGFloat)
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 计算角度范围（基于占比）
        let cumulativeStart = segment.startAngle
        let angleSpan = Angle(degrees: segment.percentage * 360)

        // 绘制弧
        let startAngle = cumulativeStart
        let endAngle = cumulativeStart + angleSpan

        // 外弧
        path.addArc(
            center: center,
            radius: radius.outer,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // 连接到内弧
        path.addArc(
            center: center,
            radius: radius.inner,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Segment Angle Calculation

extension SunburstData {
    /// 为所有 segment 递归预计算起始角度（避免渲染时重复计算 UUID hash）
    fileprivate mutating func assignAngles() {
        var cumulative: Double = 0
        for i in 0..<innerRing.count {
            innerRing[i].startAngle = .degrees(cumulative)
            let pct = innerRing[i].percentage
            cumulative += pct * 360

            var childCumulative: Double = 0
            for j in 0..<innerRing[i].children.count {
                innerRing[i].children[j].startAngle = .degrees(
                    (innerRing[i].startAngle.degrees + childCumulative)
                )
                let childPct = innerRing[i].children[j].percentage
                childCumulative += childPct * 360
            }
        }
    }
}

extension Angle {
    fileprivate var degrees: Double {
        if self == .zero { return 0 }
        return self.radians * 180 / .pi
    }
}

// MARK: - Preview Helper

extension SunburstData {
    /// 从分类文件数据构建 Sunburst 数据
    static func build(from categorized: [FileItem.FileCategory: [FileItem]]) -> SunburstData {
        var innerRing: [SunburstSegment] = []
        var totalSize: Int64 = 0

        for category in FileItem.FileCategory.allCases {
            let files = categorized[category] ?? []
            let categorySize = files.reduce(0 as Int64) { $0 + $1.size }

            guard categorySize > 0 else { continue }
            totalSize += categorySize

            // 大小细分
            var sizeSegments: [SunburstSegment] = []
            let sizeRanges: [(String, Range<Int64>)] = [
                ("巨型文件 (>1GB)", 1_000_000_000..<Int64.max),
                ("大文件 (100MB-1GB)", 100_000_000..<1_000_000_000),
                ("中等文件 (10MB-100MB)", 10_000_000..<100_000_000),
                ("小文件 (<10MB)", 0..<10_000_000)
            ]

            for (label, range) in sizeRanges {
                let rangeFiles = files.filter { range.contains($0.size) }
                let rangeSize = rangeFiles.reduce(0 as Int64) { $0 + $1.size }
                guard rangeSize > 0 else { continue }

                // 来源细分
                let sourceGroups = Dictionary(grouping: rangeFiles) { file -> String in
                    let dir = file.url.deletingLastPathComponent().lastPathComponent
                    return dir.isEmpty ? "根目录" : dir
                }
                .sorted { $0.value.reduce(0 as Int64) { $0 + $1.size } > $1.value.reduce(0 as Int64) { $0 + $1.size } }
                .prefix(5)

                let sourceSegments = sourceGroups.map { (dir, dirFiles) -> SunburstSegment in
                    let dirSize = dirFiles.reduce(0 as Int64) { $0 + $1.size }
                    return SunburstSegment(
                        category: category,
                        label: dir,
                        size: dirSize,
                        fileCount: dirFiles.count,
                        children: []
                    )
                }

                sizeSegments.append(
                    SunburstSegment(
                        category: category,
                        label: label,
                        size: rangeSize,
                        fileCount: rangeFiles.count,
                        children: sourceSegments
                    )
                )
            }

            innerRing.append(
                SunburstSegment(
                    category: category,
                    label: category.rawValue,
                    size: categorySize,
                    fileCount: files.count,
                    children: sizeSegments
                )
            )
        }

        var data = SunburstData(innerRing: innerRing, totalSize: totalSize)
        data.assignAngles()
        return data
    }
}
