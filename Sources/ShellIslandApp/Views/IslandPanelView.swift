import SwiftUI
import ShellIslandCore

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.3)

struct IslandPanelView: View {
    @ObservedObject var model: AppModel
    @State private var showsSettingsPanel = false

    private var primaryRunningTaskKind: TaskKind? {
        model.taskState.runningTasks.first?.kind
    }

    /// 收起态总宽度：始终为刘海宽度的1.3倍
    private var closedTotalWidth: CGFloat {
        // Two collapsed modes:
        // - idle: shrink width + hide side indicators
        // - active: keep classic "normal" collapsed width
        closedNotchWidth * (model.runningCount > 0 ? 1.3 : 1.0)
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
                    OpenedHeaderView(
                        onCollapse: { model.hideOverlay() },
                        onToggleSettings: {
                            withAnimation(.smooth(duration: 0.22)) {
                                showsSettingsPanel.toggle()
                            }
                        }
                    )
                        .frame(height: closedNotchHeight)
                } else {
                    CollapsedHeaderView(
                        closedNotchWidth: closedNotchWidth,
                        sideExpansionWidth: sideExpansionWidth,
                        closedNotchHeight: closedNotchHeight,
                        runningCount: model.runningCount,
                        indicator: model.collapsedStatusIndicator
                    )
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

    // MARK: - Expanded Content

    private var expandedContent: some View {
        IslandExpandedContentView(model: model, showsSettingsPanel: $showsSettingsPanel)
    }
}

// Moved to PointingHandCursorModifier.swift
