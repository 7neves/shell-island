import SwiftUI
import ShellIslandCore

struct IslandExpandedContentView: View {
    @ObservedObject var model: AppModel
    @Binding var showsSettingsPanel: Bool

    var body: some View {
        VStack(spacing: 0) {
            taskListHeader

            if !model.setupState.isReady {
                SetupBannerView(model: model)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            if showsSettingsPanel {
                SettingsPanelView(model: model)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }

            Group {
                if model.taskState.tasks.isEmpty {
                    TaskEmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    TaskListView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }

            Divider().padding(.horizontal, 14)

            SystemStripView(model: model)
                .padding(.bottom, 5)
        }
    }

    private var runningTasks: [ObservedTask] {
        model.taskState.tasks.filter { $0.status.isRunning }
    }

    private var historyTasks: [ObservedTask] {
        model.taskState.tasks.filter { !$0.status.isRunning }
    }

    private var taskListHeader: some View {
        HStack(spacing: 10) {
            Text("Tasks")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("\(runningTasks.count) running")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)

            if !historyTasks.isEmpty {
                Text("\(historyTasks.count) history")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !historyTasks.isEmpty {
                Button("Clear") {
                    model.clearCompletedTasks()
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
