import SwiftUI

// MARK: - Radial Bar Data Models

struct RadialBarData {
    let bars: [RadialBar]
    let totalSize: Int64
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct RadialBar: Identifiable {
    let id = UUID()
    let category: FileItem.FileCategory
    let segments: [RadialBarSegment]
    let totalSize: Int64
    let fileCount: Int
}

struct RadialBarSegment: Identifiable {
    let id = UUID()
    let sizeLabel: String
    let size: Int64
    let opacity: Double
}

// MARK: - Builder

extension RadialBarData {
    /// Build radial bar data from categorized files.
    /// Only categories with size > 0 are included.
    static func build(from categorized: [FileItem.FileCategory: [FileItem]]) -> RadialBarData {
        var bars: [RadialBar] = []
        var totalSize: Int64 = 0

        for category in FileItem.FileCategory.allCases {
            let files = categorized[category] ?? []
            let categorySize = files.reduce(0 as Int64) { $0 + $1.size }

            guard categorySize > 0 else { continue }
            totalSize += categorySize

            // 4 size ranges with decreasing opacity
            let sizeRanges: [(String, Range<Int64>, Double)] = [
                (">1GB", 1_000_000_000..<Int64.max, 1.0),
                ("100MB-1GB", 100_000_000..<1_000_000_000, 0.75),
                ("10-100MB", 10_000_000..<100_000_000, 0.5),
                ("<10MB", 0..<10_000_000, 0.3)
            ]

            var segments: [RadialBarSegment] = []
            for (label, range, opacity) in sizeRanges {
                let rangeFiles = files.filter { range.contains($0.size) }
                let rangeSize = rangeFiles.reduce(0 as Int64) { $0 + $1.size }
                guard rangeSize > 0 else { continue }
                segments.append(
                    RadialBarSegment(
                        sizeLabel: label,
                        size: rangeSize,
                        opacity: opacity
                    )
                )
            }

            bars.append(
                RadialBar(
                    category: category,
                    segments: segments,
                    totalSize: categorySize,
                    fileCount: files.count
                )
            )
        }

        return RadialBarData(bars: bars, totalSize: totalSize)
    }
}

// MARK: - Radial Bar Shape

/// A filled arc segment spanning from innerRadius to outerRadius between two angles.
struct RadialBarShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        // Inner arc (reverse direction)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Radial Bar Chart View

struct RadialBarChart: View {
    let data: RadialBarData
    @State private var selectedBarID: UUID?
    @State private var animationProgress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = size / 2
            let innerRadius = maxRadius * 0.25
            let usableRadius = maxRadius - innerRadius

            let bars = Array(data.bars.sorted(by: { $0.totalSize > $1.totalSize }).prefix(8))
            let maxBarSize = bars.map(\.totalSize).max() ?? 1

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack {
                    // 3 concentric guide rings
                    ForEach(0..<3) { i in
                        let ringRadius = innerRadius + usableRadius * CGFloat(i + 1) / 3.0
                        Circle()
                            .stroke(AppTheme.border.opacity(0.3), lineWidth: 0.5)
                            .frame(width: ringRadius * 2, height: ringRadius * 2)
                            .position(center)
                    }

                    // Radial bars
                    ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                        let startAngle = Angle.degrees(-90 + Double(index) * 360.0 / Double(max(bars.count, 1)))
                        let endAngle = Angle.degrees(-90 + Double(index + 1) * 360.0 / Double(max(bars.count, 1)))
                        let gapAngle = Angle.degrees(2.0)
                        let barStart = startAngle + gapAngle
                        let barEnd = endAngle - gapAngle

                        let proportionalHeight = CGFloat(Double(bar.totalSize) / Double(maxBarSize))
                        let barHeight = usableRadius * proportionalHeight * animationProgress
                        let barOuterRadius = innerRadius + max(barHeight, 4)

                        RadialBarShape(
                            startAngle: barStart,
                            endAngle: barEnd,
                            innerRadius: innerRadius,
                            outerRadius: barOuterRadius
                        )
                        .fill(ColorPalette.color(for: bar.category))
                        .opacity(selectedBarID == nil || selectedBarID == bar.id ? 1.0 : 0.3)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedBarID = selectedBarID == bar.id ? nil : bar.id
                            }
                        }
                    }

                    // Center label
                    if let selectedID = selectedBarID,
                       let selectedBar = bars.first(where: { $0.id == selectedID }) {
                        VStack(spacing: 2) {
                            Image(systemName: selectedBar.category.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(ColorPalette.color(for: selectedBar.category))
                            Text(selectedBar.category.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(ByteCountFormatter.string(fromByteCount: selectedBar.totalSize, countStyle: .file))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(width: maxRadius * 0.4)
                        .position(center)
                    } else {
                        VStack(spacing: 2) {
                            Text("文件分类")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(data.formattedTotalSize)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accent)
                        }
                        .frame(width: maxRadius * 0.4)
                        .position(center)
                    }

                    // Tooltip: positioned right of selected bar
                    if let selectedID = selectedBarID,
                       let selectedIndex = bars.firstIndex(where: { $0.id == selectedID }) {
                        let barMidAngle = Double(selectedIndex) * 360.0 / Double(bars.count) - 90
                        let tooltipRadius = maxRadius * 0.68
                        let tx = center.x + CGFloat(cos(barMidAngle * .pi / 180)) * tooltipRadius
                        let ty = center.y + CGFloat(sin(barMidAngle * .pi / 180)) * tooltipRadius

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bars[selectedIndex].category.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(bars[selectedIndex].fileCount) 个文件")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                            Divider().background(AppTheme.border)
                            ForEach(bars[selectedIndex].segments) { segment in
                                HStack {
                                    Circle()
                                        .fill(ColorPalette.color(for: bars[selectedIndex].category).opacity(segment.opacity))
                                        .frame(width: 6, height: 6)
                                    Text(segment.sizeLabel)
                                        .font(.system(size: 11)).foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: segment.size, countStyle: .file))
                                        .font(.system(size: 10, design: .monospaced)).foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
                        .frame(width: 170)
                        .position(x: clampX(tx, width: geometry.size.width),
                                  y: clampY(ty, height: geometry.size.height))
                    }
                }
                .frame(width: size, height: size)
                .onAppear {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                        animationProgress = 1.0
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        max(100, min(width - 100, x))
    }
    private func clampY(_ y: CGFloat, height: CGFloat) -> CGFloat {
        max(80, min(height - 80, y))
    }
}
