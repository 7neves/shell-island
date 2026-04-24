import SwiftUI
import ShellIslandCore

struct IslandExpandedContentView: View {
    @ObservedObject var model: AppModel
    @Binding var showsSettingsPanel: Bool

    var body: some View {
        VStack(spacing: 0) {
            taskListHeader

            if showsSettingsPanel {
                settingsPanel
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }

            Group {
                if model.taskState.tasks.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    taskList
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }

            Divider().padding(.horizontal, 14)

            bottomSystemStrip
                .padding(.bottom, 5)
        }
    }

    private var runningTasks: [ObservedTask] {
        model.taskState.tasks.filter { $0.status.isRunning }
    }

    private var historyTasks: [ObservedTask] {
        model.taskState.tasks.filter { !$0.status.isRunning }
    }

    private var displayTasks: [ObservedTask] {
        model.taskState.tasks.sorted { lhs, rhs in
            if lhs.status.isRunning != rhs.status.isRunning {
                return lhs.status.isRunning && !rhs.status.isRunning
            }
            return lhs.startedAt > rhs.startedAt
        }
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

    private var settingsPanel: some View {
        VStack(spacing: 8) {
            settingsRow(
                label: "Launch at Login",
                trailing: AnyView(
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.preferences.launchAtLogin },
                            set: { _ in model.toggleLaunchAtLogin() }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                )
            )

            settingsRow(
                label: "Refresh Setup",
                trailing: AnyView(
                    Button("Run") {
                        model.refreshSetupState()
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                )
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func settingsRow(label: String, trailing: AnyView) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            trailing
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No tasks")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("Waiting for brew, codex, npm run…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(displayTasks) { task in
                    TaskRowView(model: model, task: task, isHistory: !task.status.isRunning)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
    }

    private var bottomSystemStrip: some View {
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

private struct TaskRowView: View {
    @ObservedObject var model: AppModel
    let task: ObservedTask
    let isHistory: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.kind.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)

                    Text(statusLabel(for: task))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor(for: task))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor(for: task).opacity(0.12))
                        .clipShape(Capsule())

                    if let project = task.projectName {
                        Text(project)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }

                Text(task.commandLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(task.duration)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    if isHistory, task.workingDirectory != nil {
                        actionButton("ReRun") {
                            model.rerunTask(task)
                        }
                    }
                    if task.sessionRef != nil {
                        actionButton("Open") {
                            model.jumpToTask(task)
                        }
                    }

                    if task.status.isRunning {
                        actionButton("Stop", tint: .red, backgroundOpacity: 0.16) {
                            model.terminateTask(task)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusColor(for task: ObservedTask) -> Color {
        if task.status.isRunning { return .green }
        return .gray
    }

    private func statusLabel(for task: ObservedTask) -> String {
        switch task.status {
        case .running:
            return "RUNNING"
        case .succeeded:
            return "DONE"
        case .failed:
            return "FAIL"
        case .terminated:
            return "STOP"
        }
    }

    private func actionButton(
        _ title: String,
        tint: Color = .white,
        backgroundOpacity: Double = 0.08,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(tint.opacity(backgroundOpacity))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

