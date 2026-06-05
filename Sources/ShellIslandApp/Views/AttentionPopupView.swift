import SwiftUI
import ShellIslandCore

struct AttentionPopupView: View {
    @ObservedObject var model: AppModel
    let items: [AttentionItem]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Color.white.opacity(0.1))
            ForEach(items) { item in
                AttentionTaskRow(model: model, item: item)
                if item.id != items.last?.id {
                    Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 10)
                }
            }
        }
        .frame(width: 360)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            Text("!")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(red: 0.98, green: 0.78, blue: 0.18)))
                .padding(.leading, 10)

            Text("NEEDS ATTENTION")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.18))
                .padding(.leading, 6)

            Spacer()

            Button(action: { model.dismissAttentionPopup() }) {
                Text("DISMISS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 30)
    }
}

// MARK: - 单行任务

private struct AttentionTaskRow: View {
    @ObservedObject var model: AppModel
    let item: AttentionItem

    var body: some View {
        if item.attentionType == .claudeCodePrompt {
            claudeCodePromptLayout
        } else {
            defaultLayout
        }
    }

    // MARK: - 默认布局（水平）

    private var defaultLayout: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.commandLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !item.hasSessionRef {
                    Text("Locating kitty tab…")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.3))
                } else {
                    Text(item.attentionType.displayLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }

            Spacer(minLength: 8)

            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Claude Code Prompt 布局（水平 + 紧凑按钮）

    private var claudeCodePromptLayout: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Claude Code")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.33))
                    if let toolName = item.hookToolName {
                        Text("\u{2192}")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.3))
                        Text(toolName)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .lineLimit(1)

                if !item.hasSessionRef {
                    Text("Locating kitty tab…")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.3))
                } else if item.isHookManaged {
                    Text("Permission Request")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.35))
                } else {
                    Text("Respond in kitty")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.orange.opacity(0.5))
                }

                if let project = item.task.workingDirectory.flatMap(compactProjectName) {
                    Text(project)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.2))
                }
            }

            Spacer(minLength: 6)

            if item.isHookManaged {
                HStack(spacing: 4) {
                    claudeCodeCapsule("Deny", bgColor: Color.white.opacity(0.12)) {
                        model.sendAttentionNo(for: item.id)
                    }
                    claudeCodeCapsule("Allow", bgColor: Color(red: 0.9, green: 0.42, blue: 0.2)) {
                        model.sendAttentionYes(for: item.id)
                    }
                }
            } else {
                actionCapsule("Open", tint: .white, enabled: item.hasSessionRef) {
                    model.openAttentionTaskTerminal(item.task)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func compactProjectName(from path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        // 用 ~ 缩短 home 目录路径
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            let relative = path.dropFirst(home.count)
            return "~" + relative
        }
        return path
    }

    private func claudeCodeCapsule(
        _ title: String,
        bgColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 操作按钮（非 Claude Code Prompt）

    @ViewBuilder
    private var actionButtons: some View {
        let disabled = !item.hasSessionRef

        switch item.attentionType {
        case .confirmation:
            HStack(spacing: 4) {
                actionCapsule("Yes", tint: .green, enabled: !disabled) {
                    model.sendAttentionYes(for: item.id)
                }
                actionCapsule("No", tint: .red, enabled: !disabled) {
                    model.sendAttentionNo(for: item.id)
                }
            }

        case .password:
            actionCapsule("Open", tint: .white, enabled: !disabled) {
                model.jumpToAttentionTask(item.task)
            }

        case .pressEnter:
            actionCapsule("Enter", tint: Color(red: 0.35, green: 0.68, blue: 0.98), enabled: !disabled) {
                model.sendAttentionEnter(for: item.id)
            }

        case .claudeCodePrompt:
            EmptyView()
        case .generic:
            actionCapsule("Open", tint: .white, enabled: !disabled) {
                model.jumpToAttentionTask(item.task)
            }
        }
    }

    private func actionCapsule(
        _ title: String,
        tint: Color,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }
}
