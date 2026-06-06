import AppKit
import SwiftUI

@MainActor
final class DockPanelController: NSObject {
    private var panel: NSPanel?
    private var hostingView: FullSizeHostingView<DockRootView>?
    private var pinnedGrid: PinnedAppsGridContainer?
    private var pinnedHeightConstraint: NSLayoutConstraint?
    private var pinnedLeadingConstraint: NSLayoutConstraint?
    private var pinnedWidthConstraint: NSLayoutConstraint?
    private var pinnedBottomConstraint: NSLayoutConstraint?
    private let mouseRouter = DockPanelMouseRouter()
    private let settings: DockSettings
    private let runningApps: RunningAppsService
    let metrics = DockPanelMetrics()
    private var isLiveResizingWidth = false
    private(set) var livePreviewWidth: CGFloat?
    private var widthResizeTracker: DockPanelWidthResizeTracker?
    private let globalDragMonitor = DockGlobalDragDropMonitor()
    private let pinnedDragFeedback = PinnedDropDragFeedback()

    init(settings: DockSettings, runningApps: RunningAppsService) {
        self.settings = settings
        self.runningApps = runningApps
        super.init()
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        if let panel, let pinnedGrid {
            mouseRouter.install(panel: panel, pinnedGrid: pinnedGrid)
            globalDragMonitor.install(panel: panel, pinnedGrid: pinnedGrid, settings: settings)
        }
        applyScreenFrame()
        pinnedGrid?.reload()
        pinnedGrid?.refreshAllCells()
        panel?.layoutIfNeeded()
        panel?.orderFrontRegardless()
        panel?.displayIfNeeded()
    }

    func hide() {
        panel?.orderOut(nil)
        mouseRouter.uninstall()
        globalDragMonitor.uninstall()
    }

    func exportScreenshot(to url: URL) -> Bool {
        guard let panel, let view = panel.contentView else { return false }
        panel.displayIfNeeded()
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        return ViewSnapshot.savePNG(of: view, to: url, background: bg, trimVertical: true)
    }

    func relayout() {
        guard !isLiveResizingWidth else { return }
        applyScreenFrame()
    }

    var dockFrameInScreenCoordinates: NSRect {
        panel?.frame ?? .zero
    }

    func presentRename(payload: RenameRequestPayload, onSave: @escaping (String) -> Void) {
        RenamePanelPresenter.shared.present(
            anchorDockFrame: dockFrameInScreenCoordinates,
            payload: payload,
            onSave: onSave
        )
    }

    private func createPanel() {
        applyMetricsFromScreen()

        let rootView = DockRootView(
            settings: settings,
            runningApps: runningApps,
            metrics: metrics,
            onLayoutChange: { [weak self] in
                self?.applyScreenFrame()
            }
        )

        let hosting = FullSizeHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = [.minSize]

        let panel = NSPanel(
            contentRect: dockFrame(for: targetScreen()),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true

        panel.isFloatingPanel = true
        panel.level = .statusBar
        // 允许系统截图 / 屏幕录制捕获 Dock 面板（默认 NSPanel 为 sharingNone，README 截图会只剩壁纸）
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let container = DockPanelContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = container

        let pinned = PinnedAppsGridContainer()
        pinned.settings = settings
        pinned.translatesAutoresizingMaskIntoConstraints = false
        pinned.onPinnedListChanged = { [weak self] in
            self?.updatePinnedOverlayLayout()
            self?.applyScreenFrame()
        }

        let dropOverlay = DockPinnedDropOverlayView()
        dropOverlay.settings = settings
        dropOverlay.translatesAutoresizingMaskIntoConstraints = false
        dropOverlay.onPinnedListChanged = { [weak self] in
            self?.pinnedGrid?.reload()
            self?.updatePinnedOverlayLayout()
            self?.applyScreenFrame()
        }

        let dragFeedbackView = DockPinnedDragFeedbackView()
        dragFeedbackView.translatesAutoresizingMaskIntoConstraints = false
        pinnedDragFeedback.attach(zoneView: dragFeedbackView)

        container.addSubview(hosting)
        container.addSubview(pinned)
        container.addSubview(dragFeedbackView)
        container.addSubview(dropOverlay)
        hosting.wantsLayer = true
        pinned.wantsLayer = true
        dragFeedbackView.wantsLayer = true
        dropOverlay.wantsLayer = true
        hosting.layer?.zPosition = 0
        pinned.layer?.zPosition = 10
        dragFeedbackView.layer?.zPosition = 15
        dropOverlay.layer?.zPosition = 20

        let pinnedHeight = pinned.heightAnchor.constraint(equalToConstant: 1)
        let pinnedLeading = pinned.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0)
        let pinnedWidth = pinned.widthAnchor.constraint(equalToConstant: 1)
        let pinnedBottom = pinned.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0)
        pinnedHeightConstraint = pinnedHeight
        pinnedLeadingConstraint = pinnedLeading
        pinnedWidthConstraint = pinnedWidth
        pinnedBottomConstraint = pinnedBottom

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            pinnedLeading,
            pinnedWidth,
            pinnedBottom,
            pinnedHeight,

            dragFeedbackView.leadingAnchor.constraint(equalTo: pinned.leadingAnchor),
            dragFeedbackView.trailingAnchor.constraint(equalTo: pinned.trailingAnchor),
            dragFeedbackView.bottomAnchor.constraint(equalTo: pinned.bottomAnchor),
            dragFeedbackView.heightAnchor.constraint(equalTo: pinned.heightAnchor),

            dropOverlay.leadingAnchor.constraint(equalTo: pinned.leadingAnchor),
            dropOverlay.trailingAnchor.constraint(equalTo: pinned.trailingAnchor),
            dropOverlay.bottomAnchor.constraint(equalTo: pinned.bottomAnchor),
            dropOverlay.heightAnchor.constraint(equalTo: pinned.heightAnchor),
        ])

        pinned.registerForDraggedTypes(AppDropPasteboard.dragTypes)
        container.pinnedDropReceiver = pinned
        dropOverlay.dragFeedback = pinnedDragFeedback
        globalDragMonitor.dragFeedback = pinnedDragFeedback

        globalDragMonitor.onPinnedListChanged = { [weak self] in
            self?.pinnedGrid?.reload()
            self?.updatePinnedOverlayLayout()
            self?.applyScreenFrame()
        }
        globalDragMonitor.install(panel: panel, pinnedGrid: pinned, settings: settings)

        self.panel = panel
        self.hostingView = hosting
        self.pinnedGrid = pinned
        DockFocusYield.panel = panel

        updatePinnedOverlayLayout()
        pinned.reload()
        mouseRouter.install(panel: panel, pinnedGrid: pinned)

        let resizeTracker = DockPanelWidthResizeTracker(settings: settings, panelController: self)
        resizeTracker.install(on: panel, in: container)
        widthResizeTracker = resizeTracker

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(workspaceAppsChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(workspaceAppsChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceAppsChanged(_ notification: Notification) {
        updatePinnedOverlayLayout()
        pinnedGrid?.reload()
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        if isLiveResizingWidth, let width = livePreviewWidth {
            applyPanelWidth(width)
            return
        }
        applyScreenFrame()
        if settings.replaceSystemDock {
            SystemDockController.scheduleCalibration(
                targetWidth: DockScreenLayout.totalReservedWidth(settings: settings)
            )
        }
    }

    func beginLiveWidthResize() {
        isLiveResizingWidth = true
        metrics.isLiveResizingWidth = true
        hostingView?.suppressesLayoutInvalidation = true
    }

    /// 拖拽中：只改 NSPanel 框架，不碰 pinned / SwiftUI 宽度
    func applyPanelWidth(_ barWidth: CGFloat) {
        guard let dockPanel = panel else { return }
        let width = min(max(barWidth, DockSettings.barWidthMin), DockSettings.barWidthMax)
        if let current = livePreviewWidth, abs(current - width) < 0.5 { return }
        livePreviewWidth = width

        let frame = DockScreenLayout.frame(for: targetScreen(), barWidth: width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dockPanel.setFrame(frame, display: false)
        CATransaction.commit()
        DockScreenLayout.recordPanelFrame(dockPanel.frame)
    }

    func commitLiveWidthResize(snappedWidth: CGFloat) {
        endLiveWidthResize()
        settings.barWidth = snappedWidth
        applyScreenFrame()
        if settings.replaceSystemDock {
            SystemDockController.scheduleCalibration(targetWidth: snappedWidth, delay: 0.7)
        }
    }

    private func endLiveWidthResize() {
        isLiveResizingWidth = false
        livePreviewWidth = nil
        metrics.isLiveResizingWidth = false
        hostingView?.suppressesLayoutInvalidation = false
    }

    private func applyScreenFrame() {
        guard let dockPanel = panel else { return }
        guard !isLiveResizingWidth else { return }
        let screen = targetScreen()
        let frame = dockFrame(for: screen)
        DockScreenLayout.pinHostScreen(screen)
        applyMetricsFromScreen()
        dockPanel.setFrame(frame, display: false)
        DockScreenLayout.recordPanelFrame(dockPanel.frame)
        updatePinnedOverlayLayout()
        pinnedGrid?.reload()
        hostingView?.invalidateIntrinsicContentSize()
        dockPanel.contentView?.layoutSubtreeIfNeeded()
    }

    private func updatePinnedOverlayLayout(barWidth: CGFloat? = nil) {
        let width = barWidth ?? settings.barWidth
        let inner = width - settings.sectionPadding * 2
        let gridHeight = settings.pinnedSectionHeight(
            barWidth: width,
            appCount: settings.pinnedApps.count
        )
        let bandHeight = max(gridHeight, settings.pinnedSquareSize)
        // 高度必须与 SwiftUI `PinnedAppsSectionPlaceholder` 一致；额外 slop 会把第一行顶到分割线上方
        pinnedHeightConstraint?.constant = bandHeight
        pinnedLeadingConstraint?.constant = settings.sectionPadding
        pinnedWidthConstraint?.constant = inner
        pinnedBottomConstraint?.constant = -settings.sectionPadding

        hostingView?.pinnedStripExclusionHeight =
            settings.sectionPadding + bandHeight + settings.pinnedDividerBlockHeight
    }

    private func applyMetricsFromScreen() {
        let screen = targetScreen()
        let visible = screen?.visibleFrame ?? .zero
        metrics.width = DockScreenLayout.totalReservedWidth(settings: settings)
        metrics.height = max(visible.height, 400)
    }

    private func dockFrame(for screen: NSScreen?) -> NSRect {
        DockScreenLayout.frame(for: screen, settings: settings)
    }

    /// 与系统程序坞同屏（`visibleFrame` 右侧被让出的那块屏），多屏时不会跟鼠标跑到别的显示器。
    private func targetScreen() -> NSScreen? {
        if let dockPanel = self.panel, dockPanel.frame.size != .zero {
            let probe = NSPoint(x: dockPanel.frame.maxX - 1, y: dockPanel.frame.midY)
            if let match = NSScreen.screens.first(where: { $0.frame.contains(probe) }) {
                return match
            }
        }
        return DockScreenLayout.hostScreen()
    }
}
