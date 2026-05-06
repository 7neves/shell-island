import SwiftUI
import ShellIslandCore

struct CollapsedHeaderView: View {
    let closedNotchWidth: CGFloat
    let sideExpansionWidth: CGFloat
    let closedNotchHeight: CGFloat
    let runningCount: Int
    let indicator: AppModel.CollapsedStatusIndicator

    var body: some View {
        if indicator == .hidden {
            Rectangle()
                .fill(Color.black)
                .frame(width: closedNotchWidth - NotchShape.closedTopRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(spacing: 0) {
                statusIcon
                .frame(width: sideExpansionWidth)
                .padding(.leading, 8)
                .padding(.vertical, 2)

                Rectangle()
                    .fill(Color.black)
                    .frame(width: closedNotchWidth - NotchShape.closedTopRadius)

                PixelNumberView(number: runningCount, color: pixelAccentColor)
                    .frame(width: sideExpansionWidth)
                    .padding(.trailing, 4)
                    .padding(.vertical, 2)
            }
            .frame(height: closedNotchHeight)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch indicator {
        case .running:
            TetrisIcon(color: pixelAccentColor)
        case .failed:
            AlarmIcon(color: pixelAccentColor)
        case .attention:
            MessageIcon(color: pixelAccentColor)
        case .succeeded:
            CheckIcon(color: pixelAccentColor)
        case .hidden:
            Color.clear
        }
    }

    private var pixelAccentColor: Color {
        switch indicator {
        case .running:
            return Color(red: 0.35, green: 0.68, blue: 0.98)
        case .failed:
            return Color(red: 0.96, green: 0.22, blue: 0.24)
        case .attention:
            return Color(red: 0.98, green: 0.78, blue: 0.18)
        case .succeeded:
            return Color(red: 0.26, green: 0.84, blue: 0.44)
        case .hidden:
            return Color.white.opacity(0.55)
        }
    }
}

// MARK: - Tetris Icon

/// 俄罗斯方块图标：每 1 秒切换，3×5 矩阵，pixelSize 略大于数字以补偿稀疏图案。
private struct TetrisIcon: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let index = Int(t / 1.0) % TetrisPiece.all.count
            PixelMatrixView(pattern: TetrisPiece.all[index].pattern, color: color, pixelSize: 2.8, spacing: 1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 7 种方块，每块 3×5 矩阵，像素点独立定制。
private struct TetrisPiece {
    let pattern: [String]

    static let all: [TetrisPiece] = [.o, .i, .t, .s, .z, .j, .l]

    static let o = TetrisPiece(pattern: ["111", "111", "111", "000", "000"]) // 9px
    static let i = TetrisPiece(pattern: ["000", "000", "111", "000", "000"]) // 3px 单行横条
    static let t = TetrisPiece(pattern: ["000", "111", "010", "010", "000"]) // 5px
    static let s = TetrisPiece(pattern: ["000", "011", "110", "000", "000"]) // 4px
    static let z = TetrisPiece(pattern: ["000", "110", "011", "000", "000"]) // 4px
    static let j = TetrisPiece(pattern: ["100", "111", "000", "000", "000"]) // 4px
    static let l = TetrisPiece(pattern: ["001", "111", "000", "000", "000"]) // 4px
}

private struct AlarmIcon: View {
    let color: Color

    var body: some View {
        PixelMatrixView(pattern: Self.pattern, color: color, pixelSize: 1.96, spacing: 0.8)
    }

    private static let pattern: [String] = [
        "00111100",
        "01111110",
        "11111111",
        "11111111",
        "11111111",
        "11111111",
        "01111110",
        "00111100"
    ]
}

private struct MessageIcon: View {
    let color: Color

    var body: some View {
        PixelMatrixView(pattern: Self.pattern, color: color, pixelSize: 1.96, spacing: 0.8)
    }

    // A simple "message" bubble.
    private static let pattern: [String] = [
        "00000000",
        "00111100",
        "01111110",
        "11011011",
        "11111111",
        "01111110",
        "00111000",
        "00010000"
    ]
}

private struct CheckIcon: View {
    let color: Color

    var body: some View {
        PixelMatrixView(pattern: Self.pattern, color: color, pixelSize: 1.96, spacing: 0.8)
    }

    private static let pattern: [String] = [
        // "success" as dot-groups: left / middle / right, each 2 dots (total 6).
        "00000000",
        "00000000",
        "11011011",
        "11011011",
        "00000000",
        "00000000",
        "00000000",
        "00000000"
    ]
}

struct OpenedHeaderView: View {
    let onCollapse: () -> Void
    let onToggleSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCollapse) {
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

            Button(action: onToggleSettings) {
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
}

