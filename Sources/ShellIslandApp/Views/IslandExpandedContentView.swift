import SwiftUI
import AppKit
import ShellIslandCore

struct IslandExpandedContentView: View {
    @ObservedObject var model: AppModel
    @Binding var showsSettingsPanel: Bool

    var body: some View {
        VStack(spacing: 0) {
            taskListHeader

            if !model.setupState.isReady {
                setupBanner
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

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
                label: "Accessibility",
                trailing: AnyView(
                    setupBadge(
                        ok: model.setupState.accessibilityGranted,
                        okText: "OK",
                        badText: "Need"
                    )
                )
            )

            settingsRow(
                label: "Kitty Remote",
                trailing: AnyView(
                    setupBadge(
                        ok: model.setupState.kittyRemoteControlReady,
                        okText: "OK",
                        badText: "Need"
                    )
                )
            )

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

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup needed")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if !model.setupState.kittyRemoteControlReady {
                Text("Add `allow_remote_control yes` to kitty.conf, then restart kitty.")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if !model.setupState.accessibilityGranted {
                    Text("Accessibility")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                    bannerButton("Open Settings") {
                        openAccessibilitySettings()
                    }
                    .help("Enable Accessibility for Shell Island Dev")
                }

                if !model.setupState.kittyRemoteControlReady {
                    Text("kitty @")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                    bannerButton("Copy config") {
                        copyKittyRemoteControlConfig()
                    }
                    .help("Copy `allow_remote_control yes` to clipboard")

                    bannerButton("Open config") {
                        openKittyConfigFolder()
                    }
                    .help("Open ~/.config/kitty/")
                }

                Spacer()

                bannerButton("Refresh") {
                    model.refreshSetupState()
                }
                .help("Re-check permissions and kitty remote control")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func setupBadge(ok: Bool, okText: String, badText: String) -> some View {
        Text(ok ? okText : badText)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(ok ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((ok ? Color.green : Color.orange).opacity(0.14))
            .clipShape(Capsule())
    }

    private func bannerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyKittyRemoteControlConfig() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("allow_remote_control yes", forType: .string)
    }

    private func openKittyConfigFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("kitty", isDirectory: true)
        NSWorkspace.shared.open(url)
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
            Text("Waiting for brew, claude, npm run…")
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
        case .running:
            return .green
        case .terminating:
            return .orange
        case .failed:
            return .red
        case .succeeded, .terminated:
            return .gray
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
        case .running:
            return "RUNNING"
        case .terminating:
            return "STOPPING"
        case .succeeded:
            return "DONE"
        case .failed:
            return "ERROR"
        case .terminated:
            return "STOP"
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

