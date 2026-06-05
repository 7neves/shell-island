import Combine
import SwiftUI
import ShellIslandCore

/// 弹窗中展示的 attention 条目
struct AttentionItem: Identifiable {
    let id: String          // task.id
    let kind: TaskKind
    let commandLine: String
    let attentionType: AttentionType
    let hasSessionRef: Bool
    let task: ObservedTask
    var hookToolName: String?     // 被请求的工具名（Bash/Write/WebFetch 等），供弹窗展示
    var isHookManaged: Bool = false  // 是否已被 hook 接管（有活跃的 session mapping）
}

@MainActor
final class AppModel: ObservableObject {
    @Published var taskState = TaskState()
    @Published var preferences = AppPreferences()
    @Published var setupState = SetupState()
    @Published var systemStats = SystemStats.zero
    @Published var isExpanded = false
    @Published var attentionTaskInfos: [String: AttentionType] = [:]
    @Published var showAttentionPopup = false

    /// 向后兼容：返回需要关注的任务 ID 集合
    var attentionTaskIDs: Set<String> {
        Set(attentionTaskInfos.keys)
    }

    /// 用户已 Dismiss 的任务 ID 集合，只要该任务仍在 attentionTaskInfos 中就保持抑制。
    /// 当任务从 attentionTaskInfos 消失时自动清理，允许后续再次弹出。
    private var dismissedAttentionTaskIDs = Set<String>()

    /// 权限请求工具名字典：taskID → toolName，供弹窗展示
    private var taskToolNames: [String: String] = [:]

    private let overlay = OverlayPanelController()
    private let taskMonitor = TaskMonitor()
    private let bridgeServer = BridgeServer()
    private let systemStatsMonitor = SystemStatsMonitor()
    private let preferencesStore: AppPreferencesStore
    private let launchAtLoginController: LaunchAtLoginControlling
    private let logger = ShellLogger(category: "AppModel")
    private var cancellables = Set<AnyCancellable>()

    var isOverlayVisible: Bool { overlay.isVisible }

    var runningCount: Int {
        taskState.runningCount
    }

    enum CollapsedStatusIndicator: Sendable, Equatable {
        case hidden
        case running
        case attention
        case failed
        case succeeded
    }

    var collapsedStatusIndicator: CollapsedStatusIndicator {
        if taskState.tasks.isEmpty { return .hidden }

        // Highest priority: attention prompts (password/y/n/etc.)
        if !attentionTaskIDs.isEmpty { return .attention }

        // If anything failed recently, show failed.
        if taskState.tasks.contains(where: { $0.status == .failed }) { return .failed }

        // If still running, show running.
        if runningCount > 0 { return .running }

        // Otherwise, show last completion status.
        if let latest = taskState.tasks.max(by: { $0.startedAt < $1.startedAt }) {
            if latest.status == .succeeded { return .succeeded }
            if latest.status == .failed { return .failed }
        }

        return .hidden
    }

    func needsAttention(_ task: ObservedTask) -> Bool {
        if attentionTaskIDs.contains(task.id) { return true }
        if task.status.isTerminating { return true }
        return false
    }

    // MARK: - Attention Popup 数据

    /// 当前可展示在弹窗中的 attention 条目（过滤已 dismiss，最多 3 条）
    var attentionPopupItems: [AttentionItem] {
        // 清理已从 attentionTaskInfos 消失的任务的 dismiss 记录
        let activeIDs = Set(attentionTaskInfos.keys)
        dismissedAttentionTaskIDs = dismissedAttentionTaskIDs.filter { activeIDs.contains($0) }

        return attentionTaskInfos
            .compactMap { (taskID, type) -> AttentionItem? in
                if dismissedAttentionTaskIDs.contains(taskID) { return nil }
                guard let task = taskState.task(id: taskID) else { return nil }
                return AttentionItem(
                    id: taskID,
                    kind: task.kind,
                    commandLine: task.displayCommandLine,
                    attentionType: type,
                    hasSessionRef: task.sessionRef != nil && task.sessionRef?.kittyLeafWindowId != 0,
                    task: task,
                    hookToolName: taskToolNames[taskID],
                    isHookManaged: bridgeServer.isTaskManagedByHook(taskID)
                )
            }
            .sorted { a, b in
                // 按优先级排序（AttentionType.allCases 顺序即优先级）
                let idxA = AttentionType.allCases.firstIndex(of: a.attentionType) ?? 99
                let idxB = AttentionType.allCases.firstIndex(of: b.attentionType) ?? 99
                return idxA < idxB
            }
            .prefix(3)
            .map { $0 }
    }

    /// 上一次弹窗条目的 ID 快照，内容相同时跳过 NSHostingView 重建
    private var lastPopupSnapshot: (isShown: Bool, ids: [String]) = (false, [])

    /// 每次 attentionTaskInfos 变化时调用，决定弹窗可见性
    func updateAttentionPopupVisibility() {
        // 展开面板已打开时，不弹 popup（展开面板自身有 NEED 徽章）
        guard !isExpanded else {
            if showAttentionPopup {
                overlay.hideAttentionPopup()
                showAttentionPopup = false
                lastPopupSnapshot = (false, [])
            }
            return
        }

        let items = attentionPopupItems
        let ids = items.map { $0.id }

        if items.isEmpty {
            if showAttentionPopup {
                overlay.hideAttentionPopup()
                showAttentionPopup = false
                lastPopupSnapshot = (false, [])
            }
            return
        }

        // 相同条目集合 + 相同显示状态 → 无需操作（避免 NSHostingView 重建闪烁）
        if showAttentionPopup, ids == lastPopupSnapshot.ids { return }
        lastPopupSnapshot = (true, ids)

        if showAttentionPopup {
            overlay.updateAttentionPopupContent(model: self, items: items)
        } else {
            showAttentionPopup = true
            overlay.showAttentionPopup(model: self, items: items)
        }
    }

    // MARK: - Attention Popup 操作

    func sendAttentionYes(for taskID: String) {
        var resolved = false
        if bridgeServer.isTaskManagedByHook(taskID) {
            resolved = bridgeServer.resolvePermission(taskID: taskID, behavior: "allow")
        } else {
            taskMonitor.sendTextToTask(id: taskID, text: "y\n")
            resolved = true
        }
        if resolved {
            dismissAttention(taskID: taskID)
        } else {
            logger.warning("sendAttentionYes: resolvePermission 失败，taskID=\(taskID)，弹窗保持打开")
        }
    }

    func sendAttentionNo(for taskID: String) {
        var resolved = false
        if bridgeServer.isTaskManagedByHook(taskID) {
            resolved = bridgeServer.resolvePermission(taskID: taskID, behavior: "deny")
        } else {
            taskMonitor.sendTextToTask(id: taskID, text: "n\n")
            resolved = true
        }
        if resolved {
            dismissAttention(taskID: taskID)
        } else {
            logger.warning("sendAttentionNo: resolvePermission 失败，taskID=\(taskID)，弹窗保持打开")
        }
    }

    func sendAttentionEnter(for taskID: String) {
        taskMonitor.sendTextToTask(id: taskID, text: "\n")
        dismissAttention(taskID: taskID)
    }

    func jumpToAttentionTask(_ task: ObservedTask) {
        guard let sessionRef = task.sessionRef else { return }
        do {
            try taskMonitor.jumpTo(sessionRef: sessionRef)
        } catch {
            logger.error("跳转 kitty 失败: \(String(describing: error))")
        }
        dismissAttention(taskID: task.id)
    }

    /// 仅跳转到 kitty，不 dismiss attention（用于非 hook 管理的 Claude Code prompt）
    func openAttentionTaskTerminal(_ task: ObservedTask) {
        guard let sessionRef = task.sessionRef else { return }
        do {
            try taskMonitor.jumpTo(sessionRef: sessionRef)
        } catch {
            logger.error("跳转 kitty 失败: \(String(describing: error))")
        }
    }

    func dismissAttentionPopup() {
        // 将当前所有 attention 任务标记为已 dismiss，直到其 attention 状态消失
        dismissedAttentionTaskIDs.formUnion(attentionTaskInfos.keys)
        overlay.hideAttentionPopup()
        showAttentionPopup = false
    }

    private func dismissAttention(taskID: String) {
        // 清除 attention 状态，让收起胶囊恢复正常
        attentionTaskInfos.removeValue(forKey: taskID)
        dismissedAttentionTaskIDs.insert(taskID)
        updateAttentionPopupVisibility()
    }

    // MARK: - Init

    init(
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        launchAtLoginController: LaunchAtLoginControlling = LaunchAtLoginController()
    ) {
        self.preferencesStore = preferencesStore
        self.launchAtLoginController = launchAtLoginController

        // 将 TaskMonitor 的状态变化转发到 AppModel
        taskMonitor.$taskState
            .receive(on: RunLoop.main)
            .assign(to: &$taskState)

        taskMonitor.$preferences
            .receive(on: RunLoop.main)
            .assign(to: &$preferences)

        taskMonitor.$setupState
            .receive(on: RunLoop.main)
            .assign(to: &$setupState)

        taskMonitor.$attentionTaskInfos
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] infos in
                guard let self else { return }
                // 终端扫描结果可能不包含 hook 已设置 attention 的任务（hook 接管后终端扫描跳过该类任务）。
                // 这里合并时保留 hook 注入的值，避免 hook attention 被终端扫描空结果冲掉导致弹窗闪烁。
                let merged = infos.merging(self.attentionTaskInfos) { _, hookValue in hookValue }
                self.attentionTaskInfos = merged
                self.updateAttentionPopupVisibility()
            }
            .store(in: &cancellables)

        systemStatsMonitor.$stats
            .receive(on: RunLoop.main)
            .assign(to: &$systemStats)

        // Keep collapsed panel width in sync with running tasks (idle vs active).
        taskMonitor.$taskState
            .map { $0.runningCount > 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasTasks in
                guard let self else { return }
                guard !self.isExpanded else { return }
                self.overlay.updateCollapsed(hasTasks: hasTasks, preferredScreenID: nil)
            }
            .store(in: &cancellables)

        var loadedPreferences = preferencesStore.load()
        loadedPreferences.launchAtLogin = launchAtLoginController.currentStatus()
        preferences = loadedPreferences
        preferencesStore.save(loadedPreferences)
        taskMonitor.applyPreferences(loadedPreferences)
    }

    func start() {
        overlay.ensurePanel(model: self, preferredScreenID: nil)
        taskMonitor.refreshSetupState()
        taskMonitor.startMonitoring()
        systemStatsMonitor.start()

        // 启动 BridgeServer（Hook 通信）
        do {
            try bridgeServer.start()
            bridgeServer.onHookEvent = { [weak self] payload in
                Task { @MainActor in
                    self?.handleClaudeHook(payload)
                }
            }
            // Hook 服务端启动后，更新 hookConfigured 状态
            refreshHookConfigStatus()
            logger.info("BridgeServer 已启动")
        } catch {
            logger.error("BridgeServer 启动失败: \(String(describing: error))")
        }

        logger.info("ShellIsland started")
    }

    func toggleOverlay() {
        if isExpanded {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    func showOverlay() {
        // 展开时隐藏 popup
        if showAttentionPopup {
            overlay.hideAttentionPopup()
            showAttentionPopup = false
        }
        overlay.show(model: self, preferredScreenID: nil)
        isExpanded = true
    }

    func hideOverlay() {
        overlay.hide(hasTasks: runningCount > 0)
        isExpanded = false
        // 收起后重新评估是否需要弹 popup
        updateAttentionPopupVisibility()
    }

    func terminateTask(_ task: ObservedTask) {
        taskMonitor.terminateTask(id: task.id)
    }

    func jumpToTask(_ task: ObservedTask) {
        guard let sessionRef = task.sessionRef else { return }
        do {
            try taskMonitor.jumpTo(sessionRef: sessionRef)
        } catch {
            logger.error("跳转 kitty 失败: \(String(describing: error))")
        }
        hideOverlay()
    }

    func clearCompletedTasks() {
        taskMonitor.clearCompletedTasks()
    }

    func rerunTask(_ task: ObservedTask) {
        taskMonitor.rerun(task: task)
    }

    func toggleLaunchAtLogin() {
        let newValue = !preferences.launchAtLogin

        do {
            try launchAtLoginController.setEnabled(newValue)
            preferences.launchAtLogin = newValue
            preferencesStore.save(preferences)
            taskMonitor.applyPreferences(preferences)
        } catch {
            logger.error("切换登录自启动失败: \(String(describing: error))")
        }
    }

    func refreshSetupState() {
        taskMonitor.refreshSetupState()
        refreshHookConfigStatus()
    }

    // MARK: - Hook 集成

    /// 处理 Claude Code Hook 事件
    private func handleClaudeHook(_ payload: ClaudeHookPayload) {
        guard let eventName = payload.eventName else {
            logger.warning("收到未知 hook 事件: \(payload.hook_event_name)")
            return
        }

        switch eventName {
        case .permissionRequest:
            handlePermissionRequest(payload)
        case .stop:
            handleStopEvent(payload)
        case .sessionStart:
            handleSessionStart(payload)
        case .preToolUse, .postToolUse, .notification:
            logger.debug("Hook 事件: \(eventName.rawValue) session=\(payload.session_id)")
        }
    }

    private func handleSessionStart(_ payload: ClaudeHookPayload) {
        guard let taskID = taskMonitor.findTaskID(byTTY: payload.terminal_tty, cwd: payload.cwd) else {
            logger.warning("Hook SessionStart: 无法匹配 TTY=\(payload.terminal_tty ?? "nil") cwd=\(payload.cwd ?? "nil")，可能尚未发现进程")
            return
        }
        // 标记该 task 已被 hook 接管，终端扫描将跳过此任务
        taskMonitor.hookManagedTaskIDs.insert(taskID)
        logger.info("Hook SessionStart → task=\(taskID) tty=\(payload.terminal_tty ?? "nil") cwd=\(payload.cwd ?? "nil") 已接管")
    }

    private func handlePermissionRequest(_ payload: ClaudeHookPayload) {
        guard let taskID = taskMonitor.findTaskID(byTTY: payload.terminal_tty, cwd: payload.cwd) else {
            logger.warning("Hook PermissionRequest: 无法匹配 TTY=\(payload.terminal_tty ?? "nil") cwd=\(payload.cwd ?? "nil") 到 task，跳过")
            return
        }

        // 注册 task→session 映射，后续 Yes/No 通过 BridgeServer 返回
        bridgeServer.register(taskID: taskID, forSession: payload.session_id)

        // 标记 hook 接管（首次 PermissionRequest 也表明 hooks 在工作）
        taskMonitor.hookManagedTaskIDs.insert(taskID)

        // 存储工具名，供弹窗展示
        taskToolNames[taskID] = payload.tool_name ?? "Unknown"

        // 清除之前的 dismiss 状态，确保新请求能重新弹窗
        dismissedAttentionTaskIDs.remove(taskID)

        // 触发 NEED 徽章
        attentionTaskInfos[taskID] = .claudeCodePrompt
        updateAttentionPopupVisibility()

        logger.info("Hook PermissionRequest → task=\(taskID) tool=\(payload.tool_name ?? "Unknown") tty=\(payload.terminal_tty ?? "nil") cwd=\(payload.cwd ?? "nil")")
    }

    private func handleStopEvent(_ payload: ClaudeHookPayload) {
        guard let taskID = taskMonitor.findTaskID(byTTY: payload.terminal_tty, cwd: payload.cwd) else {
            logger.warning("Hook Stop: 无法匹配 TTY=\(payload.terminal_tty ?? "nil") cwd=\(payload.cwd ?? "nil")，跳过")
            return
        }

        // 清除 attention 状态
        if attentionTaskInfos[taskID] == .claudeCodePrompt {
            attentionTaskInfos.removeValue(forKey: taskID)
            updateAttentionPopupVisibility()
        }

        // 清理 hook session 映射，恢复终端扫描兜底
        bridgeServer.clearTask(taskID)
        taskMonitor.hookManagedTaskIDs.remove(taskID)
        taskToolNames.removeValue(forKey: taskID)

        logger.info("Hook Stop → task=\(taskID) attention 已清除，已恢复终端扫描")
    }

    /// 检测 Hook 配置状态并更新 hookConfigured
    func refreshHookConfigStatus() {
        taskMonitor.setupState.hookConfigured = Self.isHookConfigInstalled()
    }

    /// 检查 ~/.claude/settings.json 是否包含 ShellIslandHooks 配置
    static func isHookConfigInstalled() -> Bool {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // 检查是否有 ShellIslandHooks 命令的 hook 配置
        let hookTypes: [(String, [String])] = [
            ("PermissionRequest", ["*", ""]),
            ("SessionStart", ["startup", "resume"]),
            ("Stop", ["*", ""]),
        ]

        for (hookName, _) in hookTypes {
            guard let hookConfigs = hooks[hookName] as? [[String: Any]] else { continue }
            var hasShellIslandHook = false
            for config in hookConfigs {
                guard let hookList = config["hooks"] as? [[String: Any]] else { continue }
                for hook in hookList {
                    if let cmd = hook["command"] as? String, cmd.contains("ShellIslandHooks") {
                        hasShellIslandHook = true
                        break
                    }
                }
                if hasShellIslandHook { break }
            }
            if !hasShellIslandHook { return false }
        }
        return true
    }

    /// 安装 Hook 配置到 ~/.claude/settings.json
    static func installHookConfig(hooksBinaryPath: String) throws {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        let settingsDir = (settingsPath as NSString).deletingLastPathComponent

        // 确保 .claude 目录存在
        try FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        let hookConfig: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "matcher": "startup|resume",
                        "hooks": [
                            ["type": "command", "command": hooksBinaryPath]
                        ]
                    ]
                ],
                "PermissionRequest": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": hooksBinaryPath, "timeout": 86400]
                        ]
                    ]
                ],
                "Stop": [
                    [
                        "hooks": [
                            ["type": "command", "command": hooksBinaryPath]
                        ]
                    ]
                ]
            ]
        ]

        var settings: [String: Any]
        if let existingData = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            // 合并到已有配置
            settings = existingJSON
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            if let newHooks = hookConfig["hooks"] as? [String: Any] {
                for (key, value) in newHooks {
                    hooks[key] = value
                }
            }
            settings["hooks"] = hooks
        } else {
            settings = hookConfig
        }

        let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }
}
