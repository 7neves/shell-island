import AppKit
import SwiftUI
import ShellIslandCore

@MainActor
final class OverlayPanelController {
    private static let expandedScaleFactor: CGFloat = 1.5
    private static let collapsedActiveScaleFactor: CGFloat = 1.3
    private static let collapsedIdleScaleFactor: CGFloat = 1.0
    private static let baseExpandedWidth: CGFloat = 420
    private static let baseExpandedMinHeight: CGFloat = 320

    private static let popupWidth: CGFloat = 360
    private static let popupRowHeight: CGFloat = 80
    private static let popupTitleHeight: CGFloat = 32
    private static let popupGap: CGFloat = 8

    private var panel: NotchPanel?
    private var popupPanel: NSPanel?
    private var eventMonitors = NotchEventMonitors()
    private(set) var isVisible: Bool = false

    // MARK: - 主胶囊面板

    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(
            panel,
            preferredScreenID: preferredScreenID,
            expanded: false,
            collapsedHasTasks: model.runningCount > 0,
            animated: false
        )
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = false
        startEventMonitoring(model: model)
    }

    func show(model: AppModel, preferredScreenID: String?) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(
            panel,
            preferredScreenID: preferredScreenID,
            expanded: true,
            collapsedHasTasks: true,
            animated: true
        )
        panel.makeKeyAndOrderFront(nil)
        panel.ignoresMouseEvents = false
        isVisible = true
    }

    func hide(hasTasks: Bool) {
        if let panel {
            positionPanel(panel, preferredScreenID: nil, expanded: false, collapsedHasTasks: hasTasks, animated: true)
            panel.orderFrontRegardless()
        }
        isVisible = false
    }

    func updateCollapsed(hasTasks: Bool, preferredScreenID: String?) {
        guard let panel, !isVisible else { return }
        positionPanel(panel, preferredScreenID: preferredScreenID, expanded: false, collapsedHasTasks: hasTasks, animated: true)
    }

    // MARK: - Attention Popup 面板

    func showAttentionPopup(model: AppModel, items: [AttentionItem]) {
        guard let capsulePanel = panel else { return }

        let popup = makeOrReusePopupPanel()
        popupPanel = popup

        let hostingView = NSHostingView(rootView: AttentionPopupView(model: model, items: items))
        popup.contentView = hostingView

        let height = Self.popupTitleHeight + CGFloat(items.count) * Self.popupRowHeight
        let popupFrame = popupFrame(on: capsulePanel, height: height)

        popup.setFrame(popupFrame, display: true, animate: false)
        popup.orderFrontRegardless()
    }

    func hideAttentionPopup() {
        popupPanel?.orderOut(nil)
        popupPanel = nil
    }

    func updateAttentionPopupContent(model: AppModel, items: [AttentionItem]) {
        guard let popup = popupPanel else { return }
        guard let capsulePanel = panel else { return }

        let hostingView = NSHostingView(rootView: AttentionPopupView(model: model, items: items))
        popup.contentView = hostingView

        let height = Self.popupTitleHeight + CGFloat(items.count) * Self.popupRowHeight
        let popupFrame = popupFrame(on: capsulePanel, height: height)
        popup.setFrame(popupFrame, display: true, animate: false)
    }

    // MARK: - Popup Panel Creation

    private func makeOrReusePopupPanel() -> NSPanel {
        if let existing = popupPanel {
            return existing
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = false

        return panel
    }

    private func popupFrame(on capsulePanel: NSPanel, height: CGFloat) -> NSRect {
        let capsuleFrame = capsulePanel.frame
        return NSRect(
            x: capsuleFrame.midX - Self.popupWidth / 2,
            y: capsuleFrame.minY - Self.popupGap - height,
            width: Self.popupWidth,
            height: height
        )
    }

    // MARK: - Panel Creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.main
        let windowFrame = screen.map { panelFrame(on: $0, expanded: false, collapsedHasTasks: model.runningCount > 0) } ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        // Collapsed state should sit above menu bar items (e.g. Bartender) to avoid click-through menus.
        // We still downgrade to .statusBar when expanded to reduce the chance of interfering with other UI.
        panel.level = .popUpMenu
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = false

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        panel.contentView = hostingView

        return panel
    }

    // MARK: - Positioning

    private func positionPanel(
        _ panel: NSPanel,
        preferredScreenID: String?,
        expanded: Bool,
        collapsedHasTasks: Bool,
        animated: Bool
    ) {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else { return }
        panel.level = expanded ? .statusBar : .popUpMenu
        let windowFrame = panelFrame(on: screen, expanded: expanded, collapsedHasTasks: collapsedHasTasks)
        if panel.frame != windowFrame {
            panel.setFrame(windowFrame, display: true, animate: animated)
        }
    }

    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    /// 面板尺寸：收起态使用胶囊实际尺寸，展开态放大到原先设计的 1.5 倍。
    private func panelFrame(on screen: NSScreen, expanded: Bool, collapsedHasTasks: Bool) -> NSRect {
        let notchSize = screen.notchSize
        let width: CGFloat
        let height: CGFloat

        if expanded {
            width = Self.baseExpandedWidth * Self.expandedScaleFactor
            height = notchSize.height + (Self.baseExpandedMinHeight * Self.expandedScaleFactor)
        } else {
            width = notchSize.width * (collapsedHasTasks ? Self.collapsedActiveScaleFactor : Self.collapsedIdleScaleFactor)
            height = screen.islandClosedHeight
        }

        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    // MARK: - Mouse Event Monitoring

    private func startEventMonitoring(model: AppModel) {
        guard !eventMonitors.isActive else { return }

        eventMonitors.start { _ in
            // mouseMoved — 未来可扩展 hover 打开
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location, model: model)
        }
    }

    private func handleMouseDown(_ screenLocation: NSPoint, model: AppModel) {
        if model.isExpanded, !isPointInPanelArea(screenLocation) {
            model.hideOverlay()
        }
    }

    private func isPointInPanelArea(_ point: NSPoint) -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(point)
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    var isActive: Bool { globalMoveMonitor != nil }

    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint) -> Void
    ) {
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
            return event
        }
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// 收起态高度：有刘海用 safeAreaInsets.top，无刘海用菜单栏高度。
    var islandClosedHeight: CGFloat {
        safeAreaInsets.top > 0 ? safeAreaInsets.top : 24
    }
}
