import AppKit

/// Dock 面板根容器（拖放由 `PinnedAppsGridContainer` 单独处理，避免多层转发拖慢光标）
@MainActor
final class DockPanelContainerView: NSView {
    weak var pinnedDropReceiver: PinnedAppsGridContainer?
}
