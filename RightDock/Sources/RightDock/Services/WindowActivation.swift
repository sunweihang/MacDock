import AppKit

/// 统一的应用/窗口置前：仅用 `activate` + System Events，**不再**用 AX 改窗口状态（避免破坏标题栏按钮）。
@MainActor
enum WindowActivation {
    static func activateApplication(
        bundleIdentifier: String,
        pid: pid_t,
        showAllWindows: Bool
    ) {
        AppLauncher.activatePinned(
            bundleIdentifier: bundleIdentifier,
            showAllWindows: showAllWindows
        )
    }

    static func focusWindow(
        windowID: CGWindowID,
        pid: pid_t,
        bounds: CGRect,
        windowTitle: String,
        displayTitle: String,
        bundleIdentifier: String?
    ) {
        DockFocusYield.prepareForExternalActivation()
        focusWindowCore(
            windowID: windowID,
            pid: pid,
            windowTitle: windowTitle,
            displayTitle: displayTitle,
            bundleIdentifier: bundleIdentifier
        )
        finish(pid: pid)
    }

    private static func focusWindowCore(
        windowID: CGWindowID,
        pid: pid_t,
        windowTitle: String,
        displayTitle: String,
        bundleIdentifier: String?
    ) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let bundleId = bundleIdentifier ?? app.bundleIdentifier ?? ""
        let processNames = candidateProcessNames(app: app, bundleIdentifier: bundleId)

        app.activate(options: [.activateIgnoringOtherApps])

        for name in processNames {
            if windowID != 0,
               WindowFocusScript.focus(processName: name, windowID: windowID),
               focusMatchesWindow(pid: pid, windowID: windowID, windowTitle: windowTitle, displayTitle: displayTitle) {
                return
            }

            for title in WindowFocusHelper.titlesForScript(windowTitle: windowTitle, displayTitle: displayTitle) {
                if WindowFocusScript.focus(processName: name, windowTitle: title),
                   focusMatchesWindow(pid: pid, windowID: windowID, windowTitle: windowTitle, displayTitle: displayTitle) {
                    return
                }
            }
        }

        WindowFocusHelper.activateRunningApplication(
            pid: pid,
            bundleIdentifier: bundleId,
            restoreMinimized: true
        )
    }

    private static func finish(pid: pid_t) {
        DockFocusYield.finishExternalActivation(pid: pid, succeeded: verifyFrontmost(pid: pid))
    }

    static func verifyFrontmost(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    static func focusMatchesWindow(
        pid: pid_t,
        windowID: CGWindowID,
        windowTitle: String,
        displayTitle: String
    ) -> Bool {
        guard verifyFrontmost(pid: pid) else { return false }

        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if windowID != 0,
           let frontID = WindowFocusHelper.focusedWindowID(pid: pid),
           frontID == windowID {
            return true
        }

        if let focusedTitle = WindowFocusHelper.focusedWindowTitle(pid: pid) {
            if !trimmedTitle.isEmpty, titlesMatch(focusedTitle, trimmedTitle) { return true }
            if !trimmedDisplay.isEmpty, titlesMatch(focusedTitle, trimmedDisplay) { return true }
            for title in WindowFocusHelper.titlesForScript(windowTitle: windowTitle, displayTitle: displayTitle) {
                if titlesMatch(focusedTitle, title) { return true }
            }
        }

        return trimmedTitle.isEmpty && windowID == 0
    }

    private static func titlesMatch(_ focused: String, _ target: String) -> Bool {
        if focused == target { return true }
        if focused.localizedCaseInsensitiveContains(target) { return true }
        if target.localizedCaseInsensitiveContains(focused) { return true }
        return false
    }

    private static func candidateProcessNames(app: NSRunningApplication, bundleIdentifier: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func add(_ raw: String?) {
            let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            result.append(name)
        }

        add(app.localizedName)
        add(AppLauncher.displayName(forBundleIdentifier: bundleIdentifier))
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            add(url.deletingPathExtension().lastPathComponent)
        }
        return result
    }
}
