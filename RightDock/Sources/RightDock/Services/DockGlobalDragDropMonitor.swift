import AppKit

/// 访达拖放时事件在 RightDock 进程外，用全局鼠标监听 + 拖放粘贴板（需辅助功能权限）。
@MainActor
final class DockGlobalDragDropMonitor {
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private weak var panel: NSPanel?
    private weak var pinnedGrid: PinnedAppsGridContainer?
    private weak var settings: DockSettings?
    var onPinnedListChanged: (() -> Void)?
    var dragFeedback = PinnedDropDragFeedback()

    private var dragHasApplication = false

    var isInstalled: Bool { dragMonitor != nil }

    func install(panel: NSPanel, pinnedGrid: PinnedAppsGridContainer, settings: DockSettings) {
        uninstall()
        self.panel = panel
        self.pinnedGrid = pinnedGrid
        self.settings = settings

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseDragged() }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseUp() }
        }
    }

    func uninstall() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        dragMonitor = nil
        upMonitor = nil
        dragHasApplication = false
        dragFeedback.clear()
        pinnedGrid?.setDropHighlight(false)
        NSCursor.arrow.set()
    }

    private func handleMouseDragged() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.pasteboardItems?.isEmpty == false else {
            endDragSession()
            return
        }

        if !dragHasApplication {
            dragHasApplication = AppDropPasteboard.quickAcceptsApplicationDrag(pasteboard)
        }
        guard dragHasApplication else {
            endDragSession()
            return
        }

        let mouse = NSEvent.mouseLocation
        let over = dropFrameInScreen().contains(mouse)
        let nearDock = panel?.frame.insetBy(dx: -24, dy: -24).contains(mouse) == true
        pinnedGrid?.setDropHighlight(over)
        dragFeedback.update(
            draggingApplication: true,
            targeted: over,
            pasteboard: (over || nearDock) ? pasteboard : nil
        )
        if over {
            NSCursor.dragCopy.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func handleMouseUp() {
        defer { endDragSession() }
        guard dragHasApplication, let settings else { return }
        guard dropFrameInScreen().contains(NSEvent.mouseLocation) else { return }

        if PinnedAppDropper.addApplications(from: NSPasteboard(name: .drag), settings: settings) {
            onPinnedListChanged?()
            pinnedGrid?.reload()
        }
    }

    private func endDragSession() {
        dragHasApplication = false
        dragFeedback.clear()
        pinnedGrid?.setDropHighlight(false)
        NSCursor.arrow.set()
    }

    private func dropFrameInScreen() -> NSRect {
        guard let panel, let pinned = pinnedGrid, panel.isVisible else { return .zero }
        panel.contentView?.layoutSubtreeIfNeeded()
        let inWindow = pinned.convert(pinned.bounds, to: nil)
        var rect = panel.convertToScreen(inWindow)
        rect = rect.insetBy(dx: -12, dy: -12)
        return rect
    }
}
