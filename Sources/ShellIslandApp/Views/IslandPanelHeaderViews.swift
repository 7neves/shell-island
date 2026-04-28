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
                .padding(.leading, 4)
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
            RunningMatrixIcon(color: pixelAccentColor)
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

private struct RunningMatrixIcon: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            PixelMatrixView(pattern: buildPattern(t: t), color: color, pixelSize: 1.96, spacing: 0.8)
        }
    }

    /// 3列矩阵雨：每列独立速度，2个连续像素点自上而下滚动
    private func buildPattern(t: Double) -> [String] {
        // 每列的滚动速度（行/秒）和初始相位偏移（行）
        let speeds: [Double] = [2.5, 3.8, 1.9]
        let offsets: [Double] = [0.0, 2.6, 5.1]

        var grid = [[Character]](repeating: [Character](repeating: "0", count: 3), count: 8)
        for col in 0..<3 {
            let head = Int(t * speeds[col] + offsets[col]) % 8
            grid[head][col] = "1"
            grid[(head + 1) % 8][col] = "1"
        }
        return grid.map { String($0) }
    }
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

