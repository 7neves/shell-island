import SwiftUI
import ShellIslandCore

struct TaskEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("No tasks")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("Waiting for brew, claude, npm run…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

struct TaskListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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

    private var displayTasks: [ObservedTask] {
        model.taskState.tasks.sorted { lhs, rhs in
            let lhsAttention = model.needsAttention(lhs)
            let rhsAttention = model.needsAttention(rhs)
            if lhsAttention != rhsAttention {
                return lhsAttention && !rhsAttention
            }
            if lhs.status.isTerminating != rhs.status.isTerminating {
                return lhs.status.isTerminating && !rhs.status.isTerminating
            }
            if lhs.status.isRunning != rhs.status.isRunning {
                return lhs.status.isRunning && !rhs.status.isRunning
            }
            return lhs.startedAt > rhs.startedAt
        }
    }
}

private struct TaskRowView: View {
    @ObservedObject var model: AppModel
    let task: ObservedTask
    let isHistory: Bool

    @State private var stopTappedAt: Date?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.kind.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)

                    statusBadge
                        .fixedSize()

                    if model.needsAttention(task) && task.status.isRunning {
                        Text("NEED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(height: 16)
                            .background(Color.yellow.opacity(0.12))
                            .clipShape(Capsule())
                    }

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

                Text(task.displayCommandLine)
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
                    let canRerun = isHistory
                        && task.kind.isNodePackageManager
                        && task.workingDirectory != nil
                        && task.sessionRef != nil
                        && model.setupState.kittyRemoteControlReady

                    if canRerun {
                        actionButton("ReRun") {
                            model.rerunTask(task)
                        }
                    }

                    let canOpen = task.sessionRef != nil && model.setupState.kittyRemoteControlReady
                    actionButton("Open", enabled: canOpen) {
                        model.jumpToTask(task)
                    }
                    .help(openHelpText(canOpen: canOpen))

                    if task.status.isRunning {
                        actionButton("Stop", enabled: canTapStop, tint: .red, backgroundOpacity: 0.16) {
                            stopTappedAt = .now
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

    private var statusBadge: some View {
        TimelineView(.animation) { context in
            let isTerminating = task.status.isTerminating
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.75 + 0.25 * sin(t * (2 * .pi) / 0.9)
            let opacity = isTerminating ? pulse : 1.0

            Text(statusLabel(for: task))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor(for: task))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(height: 16)
                .background(statusColor(for: task).opacity(0.12))
                .clipShape(Capsule())
                .opacity(opacity)
                // Avoid implicit layout animations from frequent state updates (duration, etc.)
                .transaction { txn in
                    txn.animation = nil
                }
        }
    }

    private func statusColor(for task: ObservedTask) -> Color {
        switch task.status {
        case .running:      return .green
        case .terminating:  return .orange
        case .failed:       return .red
        case .succeeded, .terminated: return .gray
        }
    }

    private var canTapStop: Bool {
        guard let stopTappedAt else { return true }
        return Date().timeIntervalSince(stopTappedAt) > 0.8
    }

    private func openHelpText(canOpen: Bool) -> String {
        if canOpen { return "Jump to kitty tab" }
        if !model.setupState.kittyRemoteControlReady {
            return "Enable kitty remote control to use Open"
        }
        if task.sessionRef == nil {
            return "Locating kitty tab… (wait for next scan)"
        }
        return "Open is unavailable"
    }

    private func statusLabel(for task: ObservedTask) -> String {
        switch task.status {
        case .running:      return "RUNNING"
        case .terminating:  return "STOPPING"
        case .succeeded:    return "DONE"
        case .failed:       return "ERROR"
        case .terminated:   return "STOP"
        }
    }

    private func actionButton(
        _ title: String,
        enabled: Bool = true,
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
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .pointingHandCursor(enabled: enabled)
    }
}
