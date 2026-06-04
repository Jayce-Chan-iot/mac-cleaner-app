// DEPRECATED in v0.4 — Sunburst-exclusive rotation container, no longer needed
import SwiftUI

/// 轨道交互容器 —— 用于 Sunburst 的外层包装
/// 提供缩放和旋转指示器
struct OrbitalView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var hintOpacity: Double = 1.0

    var body: some View {
        ZStack {
            content()

            // 操作提示（淡入淡出）
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "hand.draw")
                    Text("拖拽旋转 · 双指缩放 · 点击下钻")
                        .font(.system(size: 11))
                }
                .foregroundColor(AppTheme.textSecondary.opacity(hintOpacity))
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            // 5 秒后淡出提示
            withAnimation(.easeOut(duration: 2).delay(5)) {
                hintOpacity = 0.2
            }
        }
    }
}

// MARK: - 模块标题栏

struct ModuleHeader: View {
    let title: String
    let icon: String
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(AppTheme.accent)

            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Label(label, systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - 扫描进度条（HUD 风格）

struct ScanProgressOverlay: View {
    let progress: Double
    let statusText: String

    var body: some View {
        VStack(spacing: 16) {
            // HUD 进度环
            ZStack {
                Circle()
                    .stroke(AppTheme.border, lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accent, Color(hex: "00A8FF"), AppTheme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
            }

            Text(statusText)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}
