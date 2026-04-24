import Combine
import SwiftUI
import ShellIslandCore

@MainActor
final class AppModel: ObservableObject {
    @Published var taskState = TaskState()
    @Published var preferences = AppPreferences()
    @Published var setupState = SetupState()
    @Published var systemStats = SystemStats.zero
    @Published var isExpanded = false

    private let overlay = OverlayPanelController()
    private let taskMonitor = TaskMonitor()
    private let systemStatsMonitor = SystemStatsMonitor()
    private let preferencesStore: AppPreferencesStore
    private let launchAtLoginController: LaunchAtLoginControlling
    private let logger = ShellLogger(category: "AppModel")
    private var cancellables = Set<AnyCancellable>()

    var isOverlayVisible: Bool { overlay.isVisible }

    var runningCount: Int {
        taskState.runningCount
    }

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

        systemStatsMonitor.$stats
            .receive(on: RunLoop.main)
            .assign(to: &$systemStats)

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
        overlay.show(model: self, preferredScreenID: nil)
        isExpanded = true
    }

    func hideOverlay() {
        overlay.hide()
        isExpanded = false
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
    }
}
