import AppKit

/// RightDock 面板贴在屏幕物理右缘；最大化窗口右缘应对齐 `dockLeftEdge`。
@MainActor
enum DockScreenLayout {
    private static var pinnedHostFrame: NSRect?
    private static var lastPanelFrame: NSRect = .zero
    private static let hostReservationThreshold: CGFloat = 6

    static func totalReservedWidth(settings: DockSettings) -> CGFloat {
        settings.barWidth
    }

    /// 系统程序坞 / RightDock 实际所在的屏幕（多屏时仅一块屏需要让出右侧）。
    static func hostScreen() -> NSScreen? {
        // 以 RightDock 面板实际位置为准（多屏时最可靠，不跟 NSScreen.main 走）
        if let match = screenContainingRightEdge(of: lastPanelFrame) {
            return match
        }

        if let frame = pinnedHostFrame,
           let match = NSScreen.screens.first(where: { $0.frame == frame }) {
            return match
        }

        let reservedScreens = NSScreen.screens.filter { systemReservedWidth(on: $0) > hostReservationThreshold }
        if let best = reservedScreens.max(by: { systemReservedWidth(on: $0) < systemReservedWidth(on: $1) }) {
            return best
        }

        // 多屏且系统 Dock 未让出右侧时，RightDock 仍在最右屏 — 不用 NSScreen.main
        return NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func pinHostScreen(_ screen: NSScreen?) {
        pinnedHostFrame = screen?.frame
    }

    static func recordPanelFrame(_ frame: NSRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        lastPanelFrame = frame
        if let screen = screenContainingRightEdge(of: frame) {
            pinHostScreen(screen)
        }
    }

    static func screensAreEqual(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.frame == rhs.frame
    }

    static func windowIsOnHostScreen(_ cgBounds: CGRect) -> Bool {
        guard let host = hostScreen(),
              let windowScreen = WindowBoundsMatcher.screenForWindow(cgBounds: cgBounds) else {
            return false
        }
        return screensAreEqual(windowScreen, host)
    }

    /// macOS 系统 Dock 的右侧占位只对主屏生效；RightDock 在最右外接屏时靠 AX 对齐即可。
    static func shouldSyncSystemDockReservation() -> Bool {
        guard let host = hostScreen(), let main = NSScreen.main else { return false }
        return screensAreEqual(host, main)
    }

    static func frame(for screen: NSScreen?, settings: DockSettings) -> NSRect {
        frame(for: screen, barWidth: settings.barWidth)
    }

    static func frame(for screen: NSScreen?, barWidth: CGFloat) -> NSRect {
        let resolved = screen ?? hostScreen()
        let screenFrame = resolved?.frame ?? NSScreen.main?.frame ?? .zero
        let visible = resolved?.visibleFrame ?? screenFrame
        let clampedWidth = min(max(barWidth, DockSettings.barWidthMin), DockSettings.barWidthMax)

        return NSRect(
            x: screenFrame.maxX - clampedWidth,
            y: visible.minY,
            width: clampedWidth,
            height: visible.height
        )
    }

    /// 最大化窗口右缘应停靠的 X（屏幕坐标，左下角原点）= RightDock 面板左缘
    static func dockLeftEdge(for screen: NSScreen?, barWidth: CGFloat) -> CGFloat {
        let clampedWidth = min(max(barWidth, DockSettings.barWidthMin), DockSettings.barWidthMax)
        if let host = hostScreen(),
           screensAreEqual(screen, host),
           lastPanelFrame.width > 1,
           screensAreEqual(screenContainingRightEdge(of: lastPanelFrame), host) {
            return lastPanelFrame.minX
        }
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        return screenFrame.maxX - clampedWidth
    }

    /// 系统为右侧 Dock 实际让出的宽度（用于校准 tilesize）。
    static func systemReservedWidth(on screen: NSScreen?) -> CGFloat {
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        let visible = screen?.visibleFrame ?? screenFrame
        return max(0, screenFrame.maxX - visible.maxX)
    }

    private static func screenContainingRightEdge(of frame: NSRect) -> NSScreen? {
        guard frame.width > 1, frame.height > 1 else { return nil }
        let probe = NSPoint(x: frame.maxX - 1, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(probe) }
    }
}
