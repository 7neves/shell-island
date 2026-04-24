import SwiftUI
import ShellIslandCore

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.3)

struct IslandPanelView: View {
    @ObservedObject var model: AppModel
    @State private var showsSettingsPanel = false

    private var completedCount: Int {
        model.taskState.tasks.filter(\.status.isCompleted).count
    }

    private var primaryRunningTaskKind: TaskKind? {
        model.taskState.runningTasks.first?.kind
    }

    /// 收起态总宽度：始终为刘海宽度的1.3倍
    private var closedTotalWidth: CGFloat {
        closedNotchWidth * 1.3
    }

    /// 左右各侧扩展宽度
    private var sideExpansionWidth: CGFloat {
        (closedTotalWidth - closedNotchWidth) / 2
    }

    /// 收起态刘海宽度
    private var closedNotchWidth: CGFloat {
        (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.notchSize.width ?? 224
    }

    /// 收起态高度
    private var closedNotchHeight: CGFloat {
        (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main)?.islandClosedHeight ?? 24
    }

    /// 当前 NotchShape 参数
    private var currentNotchShape: NotchShape {
        model.isExpanded ? NotchShape.opened : NotchShape.closed
    }

    private var currentTransitionAnimation: Animation {
        model.isExpanded ? openAnimation : closeAnimation
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Notch Content

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        let openedWidth: CGFloat = availableSize.width - 28
        let openedHeight: CGFloat = max(closedNotchHeight, availableSize.height - 14)

        let closedTotalHeight = closedNotchHeight

        let currentWidth = model.isExpanded ? openedWidth : closedTotalWidth
        let currentHeight = model.isExpanded ? openedHeight : closedTotalHeight

        let horizontalInset: CGFloat = model.isExpanded ? 14 : 0
        // Bottom spacing is handled inside expanded content (e.g. bottom strip padding).
        // Keeping this at 0 prevents extra empty space below the bottom strip.
        let bottomInset: CGFloat = 0

        let surfaceWidth = currentWidth + (horizontalInset * 2)
        let surfaceHeight = currentHeight + bottomInset

        ZStack(alignment: .top) {
            // 背景形状
            currentNotchShape
                .fill(Color.black)
                .frame(width: surfaceWidth, height: surfaceHeight)

            // 内容层
            VStack(spacing: 0) {
                // 收起态/展开态共享的 header 区域（高度 = 刘海高度）
                if model.isExpanded {
                    openedHeader
                        .frame(height: closedNotchHeight)
                } else {
                    closedHeader
                        .frame(height: closedNotchHeight)
                }

                // 展开内容
                expandedContent
                    .frame(width: openedWidth - 24)
                    .frame(maxHeight: model.isExpanded ? currentHeight - closedNotchHeight : 0, alignment: .top)
                    .opacity(model.isExpanded ? 1 : 0)
                    .clipped()
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .padding(.horizontal, horizontalInset)
            .clipShape(currentNotchShape)
            // 顶部黑色细条与物理刘海融合
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, model.isExpanded ? NotchShape.openedTopRadius : NotchShape.closedTopRadius)
            }
            // 边框微光
            .overlay {
                currentNotchShape
                    .stroke(Color.white.opacity(model.isExpanded ? 0.07 : 0.04), lineWidth: 1)
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        .animation(currentTransitionAnimation, value: model.isExpanded)
        .animation(.smooth, value: sideExpansionWidth)
        .contentShape(Rectangle())
        .pointingHandCursor(enabled: !model.isExpanded)
        .onTapGesture {
            if !model.isExpanded {
                model.showOverlay()
            }
        }
    }

    // MARK: - Collapsed Header

    private var closedHeader: some View {
        HStack(spacing: 0) {
            // 左侧：任务状态图标
            pixelStatusAnimation
                .frame(width: sideExpansionWidth)
                .padding(.leading, 4)
                .padding(.vertical, 2)

            // 中间：刘海宽度占位（居中）
            Rectangle()
                .fill(Color.black)
                .frame(width: closedNotchWidth - NotchShape.closedTopRadius)

            // 右侧：任务数量
            PixelNumberView(number: model.runningCount, color: pixelAccentColor)
                .frame(width: sideExpansionWidth)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
        }
        .frame(height: closedNotchHeight)
    }

    private var pixelAccentColor: Color {
        guard model.runningCount > 0 else { return Color.white.opacity(0.55) }

        switch primaryRunningTaskKind {
        case .brew:
            return Color(red: 0.98, green: 0.78, blue: 0.25)
        case .codex:
            return Color(red: 0.95, green: 0.48, blue: 0.22)
        case .npmRun:
            return Color(red: 0.34, green: 0.83, blue: 0.43)
        case .none:
            return .blue
        }
    }

    private var pixelStatusAnimation: some View {
        PixelTaskAnimationView(
            kind: primaryRunningTaskKind,
            isActive: model.runningCount > 0,
            color: pixelAccentColor
        )
    }

    // MARK: - Opened Header

    private var openedHeader: some View {
        HStack(spacing: 12) {
            Button(action: { model.hideOverlay() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Spacer()

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    showsSettingsPanel.toggle()
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        IslandExpandedContentView(model: model, showsSettingsPanel: $showsSettingsPanel)
    }
}

// Moved to PointingHandCursorModifier.swift
