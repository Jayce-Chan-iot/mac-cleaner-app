import SwiftUI

// MARK: - TreeMap Data

struct TreeMapData {
    var items: [TreeMapItem]
    let totalSize: Int64

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    struct TreeMapItem: Identifiable {
        let id = UUID()
        let label: String
        let size: Int64
        let fileCount: Int
        let category: FileItem.FileCategory
        var children: [TreeMapItem] = []
    }
}

// MARK: - Builder

extension TreeMapData {
    static func build(from categorized: [FileItem.FileCategory: [FileItem]]) -> TreeMapData {
        var items: [TreeMapItem] = []
        var totalSize: Int64 = 0

        for category in FileItem.FileCategory.allCases {
            let files = categorized[category] ?? []
            let catSize = files.reduce(0 as Int64) { $0 + $1.size }
            guard catSize > 0 else { continue }
            totalSize += catSize

            // Build children for subdirectories (top 5)
            let sourceGroups = Dictionary(grouping: files) { file -> String in
                let dir = file.url.deletingLastPathComponent().lastPathComponent
                return dir.isEmpty ? "根目录" : dir
            }
            .sorted { $0.value.reduce(0 as Int64) { $0 + $1.size } > $1.value.reduce(0 as Int64) { $0 + $1.size } }
            .prefix(8)

            var children: [TreeMapData.TreeMapItem] = []
            for (dir, dirFiles) in sourceGroups {
                let dirSize = dirFiles.reduce(0 as Int64) { $0 + $1.size }
                children.append(TreeMapData.TreeMapItem(
                    label: dir, size: dirSize, fileCount: dirFiles.count, category: category, children: []
                ))
            }

            items.append(TreeMapData.TreeMapItem(
                label: category.rawValue, size: catSize, fileCount: files.count, category: category, children: children
            ))
        }

        return TreeMapData(items: items, totalSize: totalSize)
    }
}

// MARK: - Squarified Treemap Layout

struct TreeMapRect: Identifiable {
    let id = UUID()
    let rect: CGRect
    let item: TreeMapData.TreeMapItem
}

func squarifyLayout(items: [TreeMapData.TreeMapItem], in bounds: CGRect) -> [TreeMapRect] {
    guard !items.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
    let totalSize = items.map(\.size).reduce(0, +)
    guard totalSize > 0 else { return [] }

    let isHorizontal = bounds.width >= bounds.height
    let sorted = items.sorted { $0.size > $1.size }

    if sorted.count == 1 {
        return [TreeMapRect(rect: bounds, item: sorted[0])]
    }

    var result: [TreeMapRect] = []
    var offset: CGFloat = 0
    let totalLen = isHorizontal ? bounds.width : bounds.height

    for item in sorted {
        let fraction = CGFloat(Double(item.size) / Double(totalSize))
        let length = max(totalLen * fraction, 8)
        let rect: CGRect
        if isHorizontal {
            rect = CGRect(x: bounds.minX + offset, y: bounds.minY,
                          width: min(length, bounds.width - offset), height: bounds.height)
        } else {
            rect = CGRect(x: bounds.minX, y: bounds.minY + offset,
                          width: bounds.width, height: min(length, bounds.height - offset))
        }
        result.append(TreeMapRect(rect: rect, item: item))
        offset += length
        if offset >= totalLen { break }
    }

    return result
}

// MARK: - TreeMap Chart View

struct TreeMapChart: View {
    let data: TreeMapData
    @State private var selectedItemID: UUID?
    @State private var drillDown: TreeMapData? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Breadcrumb
            if drillDown != nil {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            drillDown = nil
                            selectedItemID = nil
                        }
                    } label: {
                        Label("返回总览", systemImage: "chevron.left").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered).tint(AppTheme.textSecondary)
                    Spacer()
                }
            }

            // TreeMap grid
            GeometryReader { geo in
                let bounds = CGRect(origin: .zero, size: geo.size)
                let source = drillDown ?? data
                let layout = squarifyLayout(items: source.items, in: bounds)

                ZStack(alignment: .topLeading) {
                    ForEach(layout) { cell in
                        let catColor = ColorPalette.color(for: cell.item.category)
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(catColor.opacity(0.7))
                                .overlay(
                                    Rectangle()
                                        .stroke(AppTheme.background, lineWidth: 2)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cell.item.label)
                                    .font(.system(size: min(cell.rect.width / 3.5, 14), weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: cell.item.size, countStyle: .file))
                                    .font(.system(size: min(cell.rect.width / 4.5, 11)))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(4)
                        }
                        .frame(width: max(cell.rect.width, 1), height: max(cell.rect.height, 1))
                        .position(x: cell.rect.midX, y: cell.rect.midY)
                        .onTapGesture {
                            if !cell.item.children.isEmpty {
                                withAnimation(.spring(response: 0.3)) {
                                    let childData = TreeMapData(items: cell.item.children, totalSize: cell.item.size)
                                    drillDown = childData
                                    selectedItemID = cell.item.id
                                }
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))

            // Legend
            if drillDown == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(data.items) { item in
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(ColorPalette.color(for: item.category))
                                    .frame(width: 10, height: 10)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text(item.label)
                                    .font(.system(size: 11)).foregroundColor(AppTheme.textSecondary)
                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .font(.system(size: 10, design: .monospaced)).foregroundColor(AppTheme.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }
}
