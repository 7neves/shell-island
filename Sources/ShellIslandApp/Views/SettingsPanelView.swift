import SwiftUI
import AppKit
import ShellIslandCore

struct SettingsPanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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

    private func setupBadge(ok: Bool, okText: String, badText: String) -> some View {
        Text(ok ? okText : badText)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(ok ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((ok ? Color.green : Color.orange).opacity(0.14))
            .clipShape(Capsule())
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
}

struct SetupBannerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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
}
