import SwiftUI
import ShellIslandCore

struct SystemStripView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            systemMetricTile(
                title: "CPU",
                value: "\(model.systemStats.cpuLoadPercent)%",
                accent: .blue
            )

            hudDivider

            systemMetricTile(
                title: "MEM",
                value: "\(model.systemStats.memoryUsedPercent)%",
                accent: .green
            )

            hudDivider

            systemMetricTile(
                title: "UP",
                value: "\(model.systemStats.uptimeHours)H",
                accent: .orange
            )
        }
        .frame(height: 22, alignment: .center)
        .background(Color.white.opacity(0.035))
    }

    private func systemMetricTile(title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            PixelWordView(word: title, color: accent)
                .frame(width: 16, height: 7)

            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 10)
    }
}
