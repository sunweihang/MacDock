import AppKit
import Combine
import CoreGraphics

@MainActor
final class RunningAppsService: NSObject, ObservableObject {
    @Published private(set) var runningApps: [RunningWindowItem] = []
    @Published private(set) var frontmostWindowID: CGWindowID?
    @Published private(set) var frontmostWindowTitle: String?
    @Published private(set) var frontmostPid: pid_t?

    private let settings: DockSettings
    private let ownBundleId = Bundle.main.bundleIdentifier
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var frontmostTimer: Timer?
    private var windowListTimer: Timer?
    /// 屏幕可见窗口快照，用于在关闭/新建窗口时立刻触发列表刷新
    private var lastOnScreenFingerprint: Set<OnScreenWindowFingerprint> = []

    private struct OnScreenWindowFingerprint: Hashable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    init(settings: DockSettings) {
        self.settings = settings
        super.init()
        refresh()
        subscribeToWorkspace()
        // 高亮条：快速跟前台窗口（同应用多窗口不会触发 didActivate）
        frontmostTimer = Timer.scheduledTimer(
            timeInterval: 0.12,
            target: self,
            selector: #selector(timerRefreshFrontmost),
            userInfo: nil,
            repeats: true
        )
        // 窗口列表：兜底全量刷新（最小化窗口关闭等 CG 快照捕捉不到的变化）
        windowListTimer = Timer.scheduledTimer(
            timeInterval: 0.8,
            target: self,
            selector: #selector(timerRefreshWindowList),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        frontmostTimer?.invalidate()
        windowListTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// 按 Bundle ID 去重，供设置里「从运行中添加」
    var uniqueRunningBundles: [(bundleId: String, name: String)] {
        var seen = Set<String>()
        return runningApps.compactMap { item in
            guard seen.insert(item.bundleIdentifier).inserted else { return nil }
            return (item.bundleIdentifier, item.appName)
        }
        .sorted { $0.name < $1.name }
    }

    func refresh() {
        refreshFrontmost()
        refreshWindowList()
    }

    /// 仅更新蓝色选中高亮（轻量，可高频调用）
    func refreshFrontmost() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        frontmostPid = frontApp?.processIdentifier

        if WindowFocusHelper.isTrusted(), let frontApp, frontApp.bundleIdentifier != ownBundleId {
            frontmostWindowID = WindowFocusHelper.frontmostWindowID()
            frontmostWindowTitle = WindowFocusHelper.frontmostWindowTitle()
        } else {
            frontmostWindowID = nil
            frontmostWindowTitle = nil
        }
    }

    /// 仅一条窗口条应高亮：必须属于当前前台应用，再按 windowID / 标题判定。
    func isActiveItem(_ item: RunningWindowItem) -> Bool {
        guard let frontPid = frontmostPid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        guard item.pid == frontPid else { return false }

        if let frontID = frontmostWindowID, frontID != 0 {
            return item.windowID == frontID
        }

        let itemTitle = item.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let frontTitle = frontmostWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !frontTitle.isEmpty, !itemTitle.isEmpty {
            return itemTitle == frontTitle
        }

        if item.windowID == 0 {
            let placeholders = runningApps.filter { $0.pid == frontPid && $0.windowID == 0 }
            return placeholders.count == 1 && placeholders[0].id == item.id
        }

        return false
    }

    /// 点击切换后立刻更新高亮，并短延迟再同步系统状态
    func highlightAfterFocus(item: RunningWindowItem) {
        frontmostPid = item.pid
        if item.windowID != 0 {
            frontmostWindowID = item.windowID
        }
        let title = item.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            frontmostWindowTitle = title
        }
        for delay in [0.05, 0.15, 0.35] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshFrontmost()
            }
        }
    }

    private func refreshWindowList() {
        runningApps = buildWindowItems()
        lastOnScreenFingerprint = currentOnScreenFingerprint()
    }

    /// 仅 CG 屏幕窗口，无 AX 调用，可高频比对
    private func currentOnScreenFingerprint() -> Set<OnScreenWindowFingerprint> {
        Set(
            WindowEnumerator.onScreenWindows()
                .filter { $0.pid != ownPid }
                .map { OnScreenWindowFingerprint(pid: $0.pid, windowID: $0.windowID) }
        )
    }

    private func refreshWindowListIfOnScreenChanged() {
        let fingerprint = currentOnScreenFingerprint()
        guard fingerprint != lastOnScreenFingerprint else { return }
        refreshWindowList()
    }

    private func buildWindowItems() -> [RunningWindowItem] {
        let accessibilityGranted = WindowFocusHelper.isTrusted()
        let regularApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.bundleIdentifier != ownBundleId
                && app.localizedName != nil
                && !(app.bundleIdentifier.map(AppBundlePolicy.isHelperProcess) ?? false)
        }

        let pidToApp = Dictionary(uniqueKeysWithValues: regularApps.map { ($0.processIdentifier, $0) })
        let allowedPids = Set(pidToApp.keys)
        var items: [RunningWindowItem] = []
        var titleIndex: [String: Int] = [:]

        let parsedWindows = WindowEnumerator.collectWindows(
            accessibilityGranted: accessibilityGranted,
            allowedPids: allowedPids,
            bundleIdForPid: { pidToApp[$0]?.bundleIdentifier }
        )

        for window in parsedWindows {
            guard let app = pidToApp[window.pid],
                  let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName else { continue }

            guard WindowVisibilityFilter.shouldInclude(window, bundleId: bundleId) else { continue }

            let icon = app.icon ?? AppLauncher.icon(forBundleIdentifier: bundleId)
            let baseTitle = displayTitle(appName: appName, windowTitle: window.title)
            let key = "\(bundleId)|\(baseTitle)"
            titleIndex[key, default: 0] += 1
            let dup = titleIndex[key]!
            let defaultTitle = dup > 1 ? "\(baseTitle) (\(dup))" : baseTitle
            let aliasKey = WindowAliasKey.make(
                bundleIdentifier: bundleId,
                windowTitle: window.title,
                windowID: window.windowID,
                duplicateIndex: dup
            )
            let display = settings.displayTitle(aliasKey: aliasKey, default: defaultTitle)

            items.append(RunningWindowItem(
                windowID: window.windowID,
                bundleIdentifier: bundleId,
                appName: appName,
                windowTitle: window.title,
                defaultTitle: defaultTitle,
                displayTitle: display,
                aliasKey: aliasKey,
                bounds: window.bounds,
                icon: icon,
                pid: window.pid
            ))
        }

        let sorted = items.sorted {
            if $0.appName != $1.appName { return $0.appName < $1.appName }
            return $0.displayTitle < $1.displayTitle
        }

        return sorted
    }

    private func displayTitle(appName: String, windowTitle: String) -> String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return appName }
        if trimmed.caseInsensitiveCompare(appName) == .orderedSame { return trimmed }
        return "\(appName) — \(trimmed)"
    }

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]

        for name in names {
            center.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        refresh()
    }

    @objc private func timerRefreshFrontmost() {
        refreshFrontmost()
        refreshWindowListIfOnScreenChanged()
    }

    @objc private func timerRefreshWindowList() {
        refreshWindowList()
    }
}
