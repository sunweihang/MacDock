import AppKit
import Combine
import SwiftUI

@main
struct RightDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: DockSettings.shared,
                runningApps: appDelegate.runningApps
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = DockSettings.shared
    lazy var runningApps = RunningAppsService(settings: settings)
    private var dockPanel: DockPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AccessibilityTrust.prepareOnLaunch()

        dockPanel = DockPanelController(settings: settings, runningApps: runningApps)
        dockPanel?.show()

        if settings.replaceSystemDock {
            SystemDockController.ensureReplacementActive(
                reservedWidth: DockScreenLayout.totalReservedWidth(settings: settings)
            )
        } else {
            SystemDockController.restoreSystemDock()
        }

        FullscreenLayoutEnforcer.shared.start(settings: settings)

        if settings.replaceSystemDock, DockScreenLayout.shouldSyncSystemDockReservation() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                SystemDockController.scheduleCalibration(
                    targetWidth: DockScreenLayout.totalReservedWidth(settings: self.settings),
                    delay: 0.1
                )
                self.dockPanel?.relayout()
            }
        }

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .delay(for: .milliseconds(0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dockPanel?.relayout()
            }
            .store(in: &cancellables)

        // 窗口列表变化只刷新 SwiftUI，不调整面板高度（全屏高度固定）

        setupStatusItem()
        subscribeToDockNotifications()
        subscribeToAccessibilityRecheck()

        ReadmeScreenshotExporter.runIfRequested(appDelegate: self)
    }

    func exportDockScreenshot(to url: URL) -> Bool {
        dockPanel?.exportScreenshot(to: url) ?? false
    }

    var statusBarButtonForExport: NSStatusBarButton? {
        statusItem?.button
    }

    func statusMenuForExport() -> NSMenu {
        buildStatusMenu()
    }

    private func subscribeToAccessibilityRecheck() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recheckAccessibilityAfterActivation),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func recheckAccessibilityAfterActivation() {
        _ = AccessibilityTrust.refreshForUserAction()
        statusMenu = buildStatusMenu()
        runningApps.refresh()
    }

    private func subscribeToDockNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(openSettings), name: .rightDockOpenSettings, object: nil)
        center.addObserver(self, selector: #selector(quit), name: .rightDockQuit, object: nil)
        center.addObserver(
            self,
            selector: #selector(restoreFrontWindowTitleBar),
            name: .rightDockRestoreTitleBar,
            object: nil
        )
        center.addObserver(self, selector: #selector(showDock), name: Notification.Name("rightDockShow"), object: nil)
        center.addObserver(self, selector: #selector(hideDock), name: Notification.Name("rightDockHide"), object: nil)
        center.addObserver(self, selector: #selector(handleRenameRequest), name: .rightDockRenameRequest, object: nil)
    }

    @objc private func handleRenameRequest(_ notification: Notification) {
        guard let info = notification.userInfo,
              let aliasKey = info["aliasKey"] as? String,
              let defaultTitle = info["defaultTitle"] as? String,
              let currentDisplayTitle = info["currentDisplayTitle"] as? String else {
            return
        }

        let restorePID = (info["restorePID"] as? NSNumber).map { pid_t($0.int32Value) }

        let payload = RenameRequestPayload(
            aliasKey: aliasKey,
            defaultTitle: defaultTitle,
            currentDisplayTitle: currentDisplayTitle,
            restorePID: restorePID
        )

        dockPanel?.presentRename(payload: payload) { [weak self] name in
            self?.settings.setCustomAlias(name, for: aliasKey)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        FullscreenLayoutEnforcer.shared.stop()
        SystemDockController.restoreSystemDock()
    }

    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = buildStatusMenu()

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "RightDock")
            button.imagePosition = .imageLeading
            button.title = " Dock"
            button.toolTip = "RightDock — 左键显示/置顶 Dock，右键打开菜单"
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private var statusMenu: NSMenu?

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.target = self
            return menuItem
        }

        menu.addItem(item("显示 RightDock", action: #selector(showDock), key: "r"))
        menu.addItem(item("隐藏 RightDock", action: #selector(hideDock), key: "h"))
        menu.addItem(.separator())
        menu.addItem(item("设置…", action: #selector(openSettings), key: ","))
        menu.addItem(item("恢复窗口标题栏", action: #selector(restoreFrontWindowTitleBar)))
        menu.addItem(.separator())
        if !WindowFocusHelper.isTrustedNow() {
            menu.addItem(item("重新请求辅助功能授权…", action: #selector(rerequestAccessibility)))
        }

        let axItem = NSMenuItem(
            title: AccessibilityTrust.statusMessage,
            action: WindowFocusHelper.isTrustedNow() ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        axItem.target = self
        axItem.isEnabled = WindowFocusHelper.isTrustedNow() ? false : true
        menu.addItem(axItem)

        let automationItem = NSMenuItem(
            title: AccessibilityTrust.automationStatusMessage,
            action: AccessibilityTrust.automationIsGranted() ? nil : #selector(openAutomationSettings),
            keyEquivalent: ""
        )
        automationItem.target = self
        automationItem.isEnabled = !AccessibilityTrust.automationIsGranted()
        menu.addItem(automationItem)

        menu.addItem(item("打开「自动化」设置…", action: #selector(openAutomationSettings)))
        let pathHint = NSMenuItem(
            title: "程序位置：\(WindowFocusHelper.runningExecutablePath)",
            action: nil,
            keyEquivalent: ""
        )
        pathHint.isEnabled = false
        menu.addItem(pathHint)
        let widthHint = NSMenuItem(title: "拖拽 Dock 左边缘可调节宽度", action: nil, keyEquivalent: "")
        widthHint.isEnabled = false
        menu.addItem(widthHint)
        if !settings.replaceSystemDock {
            let alignHint = NSMenuItem(
                title: "最大化未贴齐 Dock：请在设置中开启「替换系统程序坞」",
                action: nil,
                keyEquivalent: ""
            )
            alignHint.isEnabled = false
            menu.addItem(alignHint)
        }
        let pinHint = NSMenuItem(
            title: WindowFocusHelper.isTrustedNow()
                ? "从访达拖 .app 到底部图标区可固定快捷方式"
                : "固定快捷方式：需先开启辅助功能（访达拖放）",
            action: nil,
            keyEquivalent: ""
        )
        pinHint.isEnabled = false
        menu.addItem(pinHint)
        menu.addItem(.separator())
        menu.addItem(item("恢复系统程序坞（底部）", action: #selector(restoreSystemDock)))
        menu.addItem(item("退出 RightDock", action: #selector(quit), key: "q"))
        return menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusMenu = buildStatusMenu()
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            return
        }
        showDock()
    }

    @objc private func openSettings() {
        SettingsWindowPresenter.show(settings: settings, runningApps: runningApps)
    }

    @objc private func openAccessibilitySettings() {
        WindowFocusHelper.openAccessibilitySettings()
        AccessibilityTrust.invalidateCache()
    }

    @objc private func openAutomationSettings() {
        AccessibilityTrust.openAutomationSettings()
    }

    @objc private func rerequestAccessibility() {
        AccessibilityTrust.resetAndRequestAuthorization()
        statusMenu = buildStatusMenu()
        let alert = NSAlert()
        alert.messageText = "授权后请完全退出 RightDock 再打开"
        alert.informativeText = """
        1. 在辅助功能里删除旧的 RightDock，点 + 添加：
        /Applications/RightDock.app
        2. 打开开关
        3. 菜单栏 Dock → 退出 RightDock
        4. 从启动台或应用程序重新打开 RightDock
        """
        alert.runModal()
    }

    @objc private func showDock() {
        if settings.replaceSystemDock {
            SystemDockController.ensureReplacementActive(
                reservedWidth: DockScreenLayout.totalReservedWidth(settings: settings)
            )
        }
        dockPanel?.show()
        if settings.replaceSystemDock, DockScreenLayout.shouldSyncSystemDockReservation() {
            SystemDockController.scheduleCalibration(
                targetWidth: DockScreenLayout.totalReservedWidth(settings: settings),
                delay: 0.2
            )
        }
    }

    @objc private func hideDock() {
        RenamePanelPresenter.shared.dismiss()
        dockPanel?.hide()
        if settings.replaceSystemDock {
            SystemDockController.pauseReplacement()
        }
    }

    @objc private func restoreFrontWindowTitleBar() {
        if WindowTitleBarRecovery.exitNativeFullscreenForFrontmostApp() {
            return
        }
        let alert = NSAlert()
        alert.messageText = "当前前台窗口未处于 macOS 原生全屏"
        alert.informativeText = "若仍看不到红黄绿按钮，请在应用内按 ⌃⌘F，或将窗口从最大化状态缩小一次。"
        alert.runModal()
    }

    @objc private func restoreSystemDock() {
        SystemDockController.forceResetToStandardDock()
    }

    @objc private func quit() {
        FullscreenLayoutEnforcer.shared.stop()
        SystemDockController.restoreSystemDock()
        NSApp.terminate(nil)
    }
}
