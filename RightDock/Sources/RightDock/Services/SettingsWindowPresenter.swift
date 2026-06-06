import AppKit
import SwiftUI

/// 菜单栏 accessory 应用无法可靠使用 `showSettingsWindow:`，用独立窗口展示设置。
@MainActor
enum SettingsWindowPresenter {
    private static var window: NSWindow?

    static func show(settings: DockSettings, runningApps: RunningAppsService) {
        if window == nil {
            let root = SettingsView(settings: settings, runningApps: runningApps)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 520)

            let win = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "RightDock 设置"
            win.contentView = hosting
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            win.center()
            window = win
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func exportScreenshot(to url: URL) -> Bool {
        guard let window else { return false }
        window.displayIfNeeded()
        return ViewSnapshot.savePNG(of: window, to: url, padding: 0)
    }
}
