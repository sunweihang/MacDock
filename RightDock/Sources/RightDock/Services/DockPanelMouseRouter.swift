import AppKit

/// NSPanel 上子视图常收不到 mouseUp；用屏幕坐标命中快捷区，不依赖 event.window。
@MainActor
final class DockPanelMouseRouter {
    private weak var panel: NSPanel?
    private weak var pinnedGrid: PinnedAppsGridContainer?
    private var monitor: Any?
    private weak var pendingCell: PinnedIconCell?

    func install(panel: NSPanel, pinnedGrid: PinnedAppsGridContainer) {
        self.panel = panel
        self.pinnedGrid = pinnedGrid
        monitor.map { NSEvent.removeMonitor($0) }
        pendingCell = nil

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.route(event: event) {
                return nil
            }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pendingCell = nil
    }

    @discardableResult
    private func route(event: NSEvent) -> Bool {
        guard let panel, panel.isVisible, let pinnedGrid else { return false }

        let screenPoint = NSEvent.mouseLocation
        guard panel.frame.contains(screenPoint) else {
            if event.type == .leftMouseUp {
                pendingCell = nil
            }
            return false
        }

        pinnedGrid.layoutSubtreeIfNeeded()
        let pointInWindow = panel.convertPoint(fromScreen: screenPoint)
        let point = pinnedGrid.convert(pointInWindow, from: nil)

        switch event.type {
        case .leftMouseDown:
            pendingCell = pinnedGrid.cell(at: point)
            return false
        case .leftMouseUp:
            let cell = pinnedGrid.cell(at: point) ?? pendingCell
            pendingCell = nil
            guard let cell else { return false }
            cell.performActivation(showAllWindows: false)
            return true
        case .rightMouseDown:
            guard let cell = pinnedGrid.cell(at: point) else { return false }
            cell.showContextMenu(with: event)
            return true
        default:
            return false
        }
    }
}
