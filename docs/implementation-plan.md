# ShellIsland v1 实现计划

## 项目概述

创建一个 macOS 13.7+ 原生桌面应用，占用刘海下方区域，监控 kitty 终端中的 `brew`、`codex`、`npm run` 任务，提供复古像素风格 UI。

## 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **系统框架**: AppKit
- **目标平台**: macOS 13.7+
- **开发工具**: Xcode 14.3+
- **架构**: 参考 `open-vibe-island` (macOS 14+)

## 项目结构

```
shell-island/
├── Package.swift                     # Swift Package 配置
├── Sources/
│   ├── ShellIslandApp/               # 主应用 (SwiftUI + AppKit)
│   │   ├── AppModel.swift           # 中央状态管理
│   │   ├── ShellIslandApp.swift     # App 入口点
│   │   ├── OverlayPanelController.swift  # Notch 浮动窗口
│   │   └── Views/
│   │       ├── IslandPanelView.swift     # 主岛 UI
│   │       ├── CollapsedIslandView.swift # 收起态 UI
│   │       ├── ExpandedIslandView.swift   # 展开态 UI
│   │       └── TaskListView.swift         # 任务列表
│   └── ShellIslandCore/              # 核心库
│       ├── Models/
│       │   ├── ObservedTask.swift        # 任务模型
│       │   ├── TaskStatus.swift          # 任务状态
│       │   ├── TaskKind.swift            # 任务类型
│       │   ├── AppPreferences.swift      # 应用偏好
│       │   └── SetupState.swift         # 设置状态
│       ├── ProcessMonitor/
│       │   ├── TaskMonitor.swift        # 任务监控器
│       │   ├── ProcessDiscovery.swift    # 进程发现
│       │   └── KittyIntegration.swift     # kitty 集成
│       └── State/
│           ├── TaskState.swift          # 任务状态管理
│           └── TaskEvent.swift          # 任务事件
├── scripts/
│   ├── build.sh                      # 构建脚本
│   ├── run.sh                        # 运行脚本
│   └── setup-dev-signing.sh        # 开发签名设置
├── docs/
│   ├── plan.md                      # v1 规划文档
│   ├── implementation-plan.md        # 本实现计划
│   └── macOS-13.7-compatibility-analysis.md  # 兼容性分析
└── tests/
    ├── ShellIslandCoreTests/
    └── ShellIslandAppTests/
```

## 核心模块实现计划

### 1. 数据模型 (ShellIslandCore/Models/)

#### 1.1 TaskKind.swift
```swift
enum TaskKind: String, Codable, Sendable {
    case brew
    case codex
    case npmRun
    
    var displayName: String {
        switch self {
        case .brew: return "brew"
        case .codex: return "codex"
        case .npmRun: return "npm run"
        }
    }
    
    func matches(command: String) -> Bool {
        switch self {
        case .brew:
            return command.hasPrefix("brew") || command.contains("/brew/")
        case .codex:
            return command.hasPrefix("codex") || command.contains("/codex/")
        case .npmRun:
            return command.hasPrefix("npm") && command.contains("run")
        }
    }
}
```

#### 1.2 TaskStatus.swift
```swift
enum TaskStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case terminated
    
    var isRunning: Bool {
        self == .running
    }
    
    var isCompleted: Bool {
        switch self {
        case .succeeded, .failed, .terminated: return true
        case .running: return false
        }
    }
}
```

#### 1.3 ObservedTask.swift
```swift
struct ObservedTask: Identifiable, Codable, Sendable {
    let id: String                       // pid + startTime
    let kind: TaskKind
    let pid: Int32
    let startTime: Date
    var status: TaskStatus
    let commandLine: String
    let tty: String?
    var sessionRef: TerminalSessionRef?
    let startedAt: Date
    var endedAt: Date?
    var exitCode: Int32?
    
    var duration: String {
        let end = endedAt ?? Date()
        let interval = end.timeIntervalSince(startedAt)
        return formatDuration(interval)
    }
    
    static func generateID(pid: Int32, startTime: Date) -> String {
        "\(pid)-\(startTime.timeIntervalSince1970)"
    }
}
```

#### 1.4 TerminalSessionRef.swift
```swift
struct TerminalSessionRef: Codable, Sendable {
    let terminalApp: String                // 固定为 "kitty"
    let kittyWindowId: UInt64
    let kittyTabId: UInt64
    let tty: String
    
    static func unknown(forTTY: String?) -> TerminalSessionRef {
        TerminalSessionRef(
            terminalApp: "kitty",
            kittyWindowId: 0,
            kittyTabId: 0,
            tty: forTTY ?? ""
        )
    }
}
```

#### 1.5 AppPreferences.swift
```swift
struct AppPreferences: Codable, Sendable {
    var launchAtLogin: Bool = false
    var pollIntervalSeconds: Double = 1.0
    let keepCompletedUntilManualClear: Bool = true
}
```

#### 1.6 SetupState.swift
```swift
struct SetupState: Codable, Sendable {
    var accessibilityGranted: Bool = false
    var kittyRemoteControlReady: Bool = false
    
    var isReady: Bool {
        accessibilityGranted && kittyRemoteControlReady
    }
}
```

### 2. 进程监控 (ShellIslandCore/ProcessMonitor/)

#### 2.1 ProcessDiscovery.swift
```swift
struct ProcessDiscovery {
    func discoverKittyProcesses() -> [RunningProcess] {
        // 1. 使用 ps 命令获取所有进程
        // 2. 过滤 kitty 相关的进程树
        // 3. 识别 brew、codex、npm run 任务
        // 4. 收集进程元数据 (PID、TTY、命令行、工作目录）
    }
    
    func discoverTaskProcesses() -> [ProcessSnapshot] {
        // 1. 获取 kitty 进程树
        // 2. 遍历子进程，识别任务
        // 3. 使用 lsof 获取工作目录
        // 4. 返回任务快照列表
    }
}
```

**实现要点**:
- 使用 `ps -Ao pid=,ppid=,tty=,command=` 获取进程信息
- 使用 `lsof -a -p <pid> -Fn` 获取工作目录
- 递归遍历进程树，找到最外层的任务进程
- 过滤 shell 包装层 (zsh -c 等)

#### 2.2 KittyIntegration.swift
```swift
struct KittyIntegration {
    func checkRemoteControlReady() -> Bool {
        // 1. 尝试执行 `kitty @ ls`
        // 2. 检查是否返回有效 JSON
        // 3. 返回就绪状态
    }
    
    func listWindows() throws -> [KittyWindow] {
        // 1. 执行 `kitty @ ls`
        // 2. 解析 JSON 输出
        // 3. 返回窗口/标签结构
    }
    
    func findSessionRef(forTTY: String, in windows: [KittyWindow]) -> TerminalSessionRef? {
        // 1. 在窗口/标签树中查找匹配的 TTY
        // 2. 返回会话引用
    }
    
    func jumpTo(sessionRef: TerminalSessionRef) throws {
        // 1. 使用 `kitty @` 命令激活对应窗口/标签
        // 2. 错误处理
    }
}
```

**实现要点**:
- 使用 Process API 执行 kitty 命令
- JSON 解析处理响应
- 错误处理和超时管理

#### 2.3 TaskMonitor.swift
```swift
@MainActor
@Observable
final class TaskMonitor {
    var tasks: [ObservedTask] = []
    var preferences: AppPreferences
    var setupState: SetupState
    
    private var pollTimer: Timer?
    
    func startMonitoring() {
        // 1. 启动定时器 (默认 1 秒间隔)
        // 2. 开始进程发现
        // 3. 检查设置状态
    }
    
    func stopMonitoring() {
        // 1. 停止定时器
        // 2. 清理资源
    }
    
    private func poll() {
        // 1. 发现当前任务
        // 2. 更新任务状态
        // 3. 检查已完成的任务
        // 4. 更新 UI
    }
    
    func terminateTask(id: String) {
        // 1. 发送 SIGTERM
        // 2. 3 秒超时后发送 SIGKILL
        // 3. 更新任务状态
    }
    
    func clearCompletedTasks() {
        // 1. 移除所有已完成的任务
        // 2. 更新 UI
    }
}
```

### 3. 状态管理 (ShellIslandCore/State/)

#### 3.1 TaskEvent.swift
```swift
enum TaskEvent: Sendable {
    case taskDiscovered(ObservedTask)
    case taskStatusChanged(String, TaskStatus)
    case taskTerminated(String, Int32?)
    case taskCompleted(String, Int32?)
    case sessionRefUpdated(String, TerminalSessionRef?)
}

extension TaskEvent: Equatable {}
```

#### 3.2 TaskState.swift
```swift
struct TaskState: Equatable, Sendable {
    private(set) var tasksByID: [String: ObservedTask]
    
    init(tasks: [ObservedTask] = []) {
        self.tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }
    
    var tasks: [ObservedTask] {
        tasksByID.values.sorted { $0.startedAt > $1.startedAt }
    }
    
    var runningTasks: [ObservedTask] {
        tasksByID.values.filter { $0.status == .running }
            .sorted { $0.startedAt > $1.startedAt }
    }
    
    var runningCount: Int {
        tasksByID.values.filter { $0.status == .running }.count
    }
    
    mutating func apply(_ event: TaskEvent) {
        switch event {
        case let .taskDiscovered(task):
            tasksByID[task.id] = task
            
        case let .taskStatusChanged(id, status):
            tasksByID[id]?.status = status
            
        case let .taskTerminated(id, exitCode):
            tasksByID[id]?.endedAt = .now
            tasksByID[id]?.exitCode = exitCode
            tasksByID[id]?.status = .terminated
            
        case let .taskCompleted(id, exitCode):
            tasksByID[id]?.endedAt = .now
            tasksByID[id]?.exitCode = exitCode
            let exit = exitCode ?? 0
            tasksByID[id]?.status = exit == 0 ? .succeeded : .failed
            
        case let .sessionRefUpdated(id, sessionRef):
            tasksByID[id]?.sessionRef = sessionRef
        }
    }
    
    mutating func removeCompletedTasks() {
        tasksByID = tasksByID.filter { !$0.value.status.isCompleted }
    }
    
    func task(id: String) -> ObservedTask? {
        tasksByID[id]
    }
}
```

### 4. UI 实现 (ShellIslandApp)

#### 4.1 ShellIslandApp.swift
```swift
@main
struct ShellIslandApp: App {
    @State private var model = AppModel()
    
    var body: some Scene {
        WindowGroup {
            EmptyView()  // Agent app，无主窗口
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Command("quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
```

#### 4.2 AppModel.swift
```swift
@MainActor
@Observable
final class AppModel {
    var taskState = TaskState()
    var preferences = AppPreferences()
    var setupState = SetupState()
    
    @ObservationIgnored private let overlay = OverlayPanelController()
    @ObservationIgnored private let taskMonitor = TaskMonitor()
    
    var isOverlayVisible: Bool { overlay.isVisible }
    
    init() {
        // 1. 加载偏好设置
        // 2. 初始化任务监控器
        // 3. 检查设置状态
        // 4. 启动监控
    }
    
    func start() {
        overlay.ensurePanel(model: self, preferredScreenID: nil)
        taskMonitor.startMonitoring()
    }
    
    func toggleOverlay() {
        if overlay.isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
    
    func showOverlay() {
        overlay.show(model: self, preferredScreenID: nil)
    }
    
    func hideOverlay() {
        overlay.hide()
    }
    
    func terminateTask(_ task: ObservedTask) {
        taskMonitor.terminateTask(id: task.id)
    }
    
    func jumpToTask(_ task: ObservedTask) {
        guard let sessionRef = task.sessionRef else { return }
        try? KittyIntegration().jumpTo(sessionRef: sessionRef)
        hideOverlay()
    }
    
    func clearCompletedTasks() {
        taskMonitor.clearCompletedTasks()
    }
    
    func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        // 更新登录自启动设置
    }
}
```

#### 4.3 OverlayPanelController.swift
```swift
@MainActor
final class OverlayPanelController {
    private static let collapsedWidth: CGFloat = 224  // 标准 Notch 宽度
    private static let collapsedHeight: CGFloat = 38   // 标准 Notch 高度
    private static let expandedWidth: CGFloat = 320
    private static let expandedContentPadding: CGFloat = 16
    
    private var panel: NSPanel?
    private(set) var isVisible: Bool = false
    
    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(panel, preferredScreenID: preferredScreenID)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
    }
    
    func show(model: AppModel, preferredScreenID: String?) {
        let panel = self.panel ?? make()Panel(model: model)
        self.panel = panel
        positionPanel(panel, preferredScreenID: preferredScreenID)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = false
        isVisible = true
    }
    
    func hide() {
        panel?.ignoresMouseEvents = true
        isVisible = false
    }
    
    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.main
        let windowFrame = panelFrame(for: model, on: screen)
        
        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = true
        
        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        panel.contentView = hostingView
        
        return panel
    }
    
    private func positionPanel(_ panel: NSPanel, preferredScreenID: String?) {
        guard let screen = resolveTargetScreen(preferredScreenID) else { return }
        let windowFrame = panelFrame(for: model, on: screen)
        panel.setFrame(windowFrame, display: true)
    }
    
    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        
        // 优先选择有刘海的屏幕
        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }
        
        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        
        return NSScreen.main ?? screens[0]
    }
    
    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let notchSize = screen.notchSize
        // 展开状态下的尺寸
        let width = expandedWidth
        let height = notchSize.height + estimateContentHeight(for: model)
        
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
    
    private func estimateContentHeight(for model: AppModel?) -> CGFloat {
        guard let model else { return 120 }
        
        let taskCount = model.taskState.tasks.count
        let baseHeight: CGFloat = 120
        let taskRowHeight: CGFloat = 60
        let spacing: CGFloat = 8
        
        return baseHeight + CGFloat(taskCount) * taskRowHeight + CGFloat(max(0, taskCount - 1)) * spacing
    }
}
```

#### 4.4 IslandPanelView.swift
```swift
struct IslandPanelView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            if model.isOverlayVisible {
                ExpandedIslandView(model: model)
            } else {
                CollapsedIslandView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// Notch 面板自定义 NSPanel
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// NotchHostingView：透明背景的 Hosting View
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }
    
    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
```

#### 4.5 CollapsedIslandView.swift
```swift
struct CollapsedIslandView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        HStack(spacing: 8) {
            // 左侧：像素状态区
            PixelStatusIndicator(
                status: overallStatus(for: model),
                hasRunningTasks: model.taskState.runningCount > 0
            )
            
            // 右侧：像素数字
            PixelCounter(count: model.taskState.runningCount)
        }
        .frame(width: OverlayPanelController.collapsedWidth, height: OverlayPanelController.collapsedHeight)
        .background(pixelArtBackground)
        .onTapGesture {
            withAnimation {
                model.showOverlay()
            }
        }
    }
    
    private func overallStatus(for model: AppModel) -> TaskStatus? {
        let runningTasks = model.taskState.runningTasks
        return runningTasks.first?.status
    }
}
```

#### 4.6 ExpandedIslandView.swift
```swift
struct ExpandedIslandView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
           收起按钮
            TaskHeaderView(model: model)
            
            // 任务列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.taskState.tasks) { task in
                        TaskRowView(task: task, model: model)
                    }
                }
                .padding()
            }
            
            // 底部操作区
            BottomControls(model: model)
        }
        .frame(width: OverlayPanelController.expandedWidth)
        .background(pixelArtBackground)
        .cornerRadius(12)
    }
}

struct TaskHeaderView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        HStack {
            Button(action: { model.hideOverlay() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Text("Shell Island")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct BottomControls: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        VStack(spacing: 12) {
            // "Clear Completed" 按钮
            if model.taskState.tasks.contains(where: { $0.status.isCompleted }) {
                Button(action: { model.clearCompletedTasks() }) {
                    Text("Clear Completed")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
            
            // "Launch at Login" 开关
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 12, weight: .medium))
                
                Toggle("", isOn: Binding(
                    get: { model.preferences.launchAtLogin },
                    set: { _ in model.toggleLaunchAtLogin() }
                ))
                .toggleStyle(.switch)
            }
            
            // 设置状态提示
            SetupStatusIndicator(setupState: model.setupState)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

#### 4.7 TaskRowView.swift
```swift
struct TaskRowView: View {
    let task: ObservedTask
    @ObservedObject var model: AppModel
    
    var body: some View {
        VStack(spacing: 8) {
            // 任务信息行
            HStack {
                // 命令名
                Text(task.kind.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // 状态
                TaskStatusBadge(status: task.status)
            }
            
            // 命令详情
            if let commandName = extractCommandName(from: task.commandLine) {
                HStack {
                    Text(commandName)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // 时长或结果
                    if task.status == .running {
                        Text(task.duration)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(task.status.displayResult(task.exitCode))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(task.status.resultColor)
                    }
                }
            }
            
            // 操作按钮
            HStack(spacing: 8) {
                // Open 按钮
                Button(action: { model.jumpToTask(task) }) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(task.sessionRef == nil)
                
                // Stop 按钮
                if task.status == .running {
                    Button(action: { model.terminateTask(task) }) {
                        Label("Stop", systemImage: "xmark.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

enum TaskStatus {
    func displayResult(_ exitCode: Int32?) -> String {
        switch self {
        case .succeeded:
            return "Success"
        case .failed:
            return "Failed"
        case .terminated:
            return "Terminated"
        case .running:
            return "Running"
        }
    }
    
    var resultColor: Color {
        switch self {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .terminated:
            return .orange
        case .running:
            return .blue
        }
    }
}
```

### 5. 像素风格 UI 组件

#### 5.1 PixelStatusIndicator.swift
```swift
struct PixelStatusIndicator: View {
    let status: TaskStatus?
    let hasRunningTasks: Bool
    
    var body: some View {
        ZStack {
            // 背景像素块
            Rectangle()
                .fill(statusColor)
                .frame(width: 16, height: 16)
                .cornerRadius(2)
            
            // 状态图标/动画
            if hasRunningTasks {
                PixelActivityIndicator(isAnimating: status == .running)
            }
        }
        .frame(width: 24, height: 24)
    }
    
    private var statusColor: Color {
        guard let status = status else {
            return Color.secondary.opacity(0.3)  // Idle 颢色
        }
        
        switch status {
        case .running:
            return Color(red: 0.43, green: 0.62, blue: 1.0)  // #6E9FFF
        case .succeeded:
            return Color(red: 0.26, green: 0.91, blue: 0.42)  // #42E86B
        case .failed:
            return Color(red: 1.0, green: 0.71, blue: 0.27)  // #FFB547
        case .terminated:
            return Color.orange
        }
    }
}

struct PixelActivityIndicator: View {
    let isAnimating: Bool
    
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(rotation))
            .opacity(0.8)
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
```

#### 5.2 PixelCounter.swift
```swift
struct PixelCounter: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(count).compactMap { $0 }), id: \.self) { digit in
                PixelDigit(digit: digit)
            }
        }
    }
}

struct PixelDigit: View {
    let digit: Character
    
    var body: some View {
        Text(String(digit))
            .font(.custom("PixelFont", size: 16))
            .foregroundStyle(.primary)
            .frame(width: 10, height: 16)
            .background(digit == "0" ? Color.clear : Color.secondary.opacity(0.2))
            .cornerRadius(2)
    }
}
```

#### 5.3 pixelArtBackground.swift
```swift
extension ShapeStyle where Content == Color {
    static var pixelArtBackground: some ShapeStyle {
        // 实现像素风格背景
        // 可以使用图案或纹理
        return .linearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.15),
                Color(red: 0.15, green: 0.15, blue: 0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

## 实施步骤

### Phase 1: 项目脚手架搭建 (Day 1)

**目标**: 创建基本项目结构和配置

- [ ] 创建 Swift Package 项目
- [ ] 配置 `Package.swift` (macOS 13.7, Swift 5.9+)
- [ ] 创建项目目录结构
- [ ] 配置基本编译环境
- [ ] 验证编译成功

### Phase 2: 核心数据模型 (Day 1-2)

**目标**: 实现所有数据模型

- [ ] 实现 `TaskKind.swift`
- [ ] 实现 `TaskStatus.swift`
- [ ] 实现 `ObservedTask.swift`
- [ ] 实现 `TerminalSessionRef.swift`
- [ ] 实现 `AppPreferences.swift`
- [ ] 实现 `SetupState.swift`
- [ ] 添加单元测试

### Phase 3: 进程监控核心 (Day 2-3)

**目标**: 实现进程发现和监控

- [ ] 实现 `ProcessDiscovery.swift`
- [ ] 实现 `KittyIntegration.swift`
- [ ] 实现 `TaskMonitor.swift`
- [ ] 实现 `TaskEvent.swift`
- [ ] 实现 `TaskState.swift`
- [ ] 添加进程监控测试

### Phase 4: 基础 UI 框架 (Day 3-4)

**目标**: 创建基本 UI 结构

- [ ] 实现 `ShellIslandApp.swift`
- [ ] 实现 `AppModel.swift`
- [ ] 实现 `OverlayPanelController.swift`
- [ ] 实现 `IslandPanelView.swift`
- [ ] 实现 `NotchPanel` 和 `NotchHostingView`
- [ ] 验证 UI 可以显示

### Phase 5: 收起态 UI (Day 4-5)

**目标**: 实现像素风格收起界面

- [ ] 实现 `CollapsedIslandView.swift`
- [ ] 实现 `PixelStatusIndicator.swift`
- [ ] 实现 `PixelCounter.swift`
- [ ] 实现像素风格背景
- [ ] 添加点击展开功能
- [ ] 验证收起/展开交互

### Phase 6: 展开态 UI (Day 5-6)

**目标**: 实现任务列表界面

- [ ] 实现 `ExpandedIslandView.swift`
- [ ] 实现 `TaskHeaderView.swift`
- [ ] 实现 `TaskRowView.swift`
- [ ] 实现 `BottomControls.swift`
- [ ] 实现任务状态显示
- [ ] 验证任务列表渲染

### Phase 7: 集成测试 (Day 6-7)

**目标**: 端到端集成测试

- [ ] 集成任务监控和 UI
- [ ] 测试 kitty 任务发现
- [ ] 测试任务状态更新
- [ ] 测试 UI 实时更新
- [ ] 测试多任务场景

### Phase 8: kitty 跳转功能 (Day 7-8)

**目标**: 实现精确跳转到 kitty 窗口/标签

- [ ] 完善 `KittyIntegration.swift`
- [ ] 实现 `jumpTo` 功能
- [ ] 测试窗口/标签切换
- [ ] 处理错误情况
- [ ] 添加 Accessibility 权限检查

### Phase 9: 任务管理功能 (Day 8-9)

**目标**: 实现任务结束和清理功能

- [ ] 实现 `terminateTask` 功能
- [ ] 实现 SIGTERM/SIGKILL 逻辑
- [ ] 实现 `clearCompletedTasks` 功能
- [ ] 测试任务终止
- [ ] 测试任务清理

### Phase 10: 登录自启动 (Day 9-10)

**目标**: 实现登录自启动功能

- [ ] 集成 `SMAppService`
- [ ] 实现 `toggleLaunchAtLogin` 功能
- [ ] 测试登录自启动
- [ ] 更新设置状态 UI

### Phase 11: 像素风格优化 (Day 10-11)

**目标**: 完善像素风格 UI

- [ ] 优化像素字体
- [ ] 添加像素图标
- [ ] 实现像素动画
- [ ] 优化颜色方案
- [ ] 测试不同状态下的视觉效果

### Phase 12: 多显示器支持 (Day 11-12)

**目标**: 支持多显示器场景

- [ ] 实现屏幕选择逻辑
- [ ] 测试外接显示器
- [ ] 测试显示器切换
- [ ] 优化 Notch 区域检测

### Phase 13: 性能优化 (Day 12-13)

**目标**: 优化性能和资源使用

- [ ] 优化进程扫描性能
- [ ] 优化 UI 渲染性能
- [ ] 减少内存占用
- [ ] 优化轮询间隔
- [ ] 性能测试

### Phase 14: 错误处理和日志 (Day 13-14)

**目标**: 完善错误处理和日志

- [ ] 实现统一错误处理
- [ ] 添加日志系统
- [ ] 实现用户友好的错误提示
- [ ] 添加调试日志输出

### Phase 15: 测试和完善 (Day 14-15)

**目标**: 全面测试和修复

- [ ] 单元测试覆盖率 > 80%
- [ ] 集成测试
- [ ] 用户接受测试
- [ ] 性能测试
- [ ] 边缘情况测试

### Phase 16: 打包和发布准备 (Day 15-16)

**目标**: 准备发布

- [ ] 配置代码签名
- [ ] 配置应用图标
- [ ] 创建 DMG 安装包
- [ ] 编写发布说明
- [ ] 准备 GitHub Release

## 测试计划

### 单元测试

- [ ] 数据模型测试 (TaskKind, TaskStatus, ObservedTask 等)
- [ ] 状态管理测试 (TaskState.apply)
- [ ] 进程发现测试 (ProcessDiscovery)
- [ ] kitty 集成测试 (KittyIntegration)
- [ ] UI 组件测试

### 集成测试

- [ ] 完整流程测试 (启动→发现任务→更新状态→显示 UI)
- [ ] kitty 任务监控测试
- [ ] kitty 跳转功能测试
- [ ] 多任务并发测试
- [ ] 任务终止测试

### 用户接受测试

- [ ] 在 macOS 13.7.7 上测试
- [ ] 在有刘海的 Mac 上测试
- [ ] 在无刘海的 Mac 上测试
- [ ] 多显示器场景测试
- [ ] 外接显示器测试

## 风险和缓解措施

### 1. 进程扫描性能

**风险**: 频繁的进程扫描可能影响系统性能
**缓解**:
- 使用高效的 `ps` 命令格式
- 限制扫描深度和范围
- 缓存结果，避免重复扫描

### 2. kitty 集成失败

**风险**: kitty remote control 未配置或失败
**缓解**:
- 提供清晰的错误提示
- 优雅降级 (禁用 Open 按钮)
- 提供配置指引

### 3. UI 渲染性能

**风险**: 任务数量多时 UI 渲染缓慢
**缓解**:
- 使用 LazyVStack
- 限制可见任务数量
- 优化视图更新频率

### 4. 内存占用

**风险**: 长时间运行可能内存泄漏
**缓解**:
- 定期清理已完成任务
- 使用 weak 引用避免循环引用
- 定期内存使用监控

## 成功标准

- [ ] 可以监控 kitty 中的 `brew`、`codex`、`npm run` 任务
- [ ] 收起态正确显示运行中任务数量
- [ ] 展开态正确显示任务列表
- [ ] 支持跳转到 kitty 窗口/标签
- [ ] 支持结束任务
- [ ] 支持清理已完成任务
- [ ] 支持登录自启动
- [ ] 像素风格 UI 符合设计
- [ ] 在 macOS 13.7+ 上稳定运行
- [ ] 通过所有测试

---

**文档版本**: 1.0
**创建日期**: 2026-04-17
**适用项目**: ShellIsland v1
