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
            for title in WindowFocusHelper.titlesForScript(windowTitle: windowTitle, displayTitle: displayTitle) {
                if WindowFocusScript.focus(processName: name, windowTitle: title),
                   focusMatchesWindow(pid: pid, windowID: windowID, windowTitle: windowTitle, displayTitle: displayTitle) {
                    return
                }
            }

            if WindowFocusScript.activateProcess(
                processName: name,
                bundleIdentifier: bundleId.isEmpty ? nil : bundleId,
                allWindows: false
            ),
               focusMatchesWindow(pid: pid, windowID: windowID, windowTitle: windowTitle, displayTitle: displayTitle) {
                return
            }
        }
    }

    private static func finish(pid: pid_t) {
        DockFocusYield.finishExternalActivation(pid: pid, succeeded: verifyFrontmost(pid: pid))
    }

    static func verifyFrontmost(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private static func focusMatchesWindow(
        pid: pid_t,
        windowID: CGWindowID,
        windowTitle: String,
        displayTitle: String
    ) -> Bool {
        guard verifyFrontmost(pid: pid) else { return false }

        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let focusedTitle = WindowFocusHelper.focusedWindowTitle(pid: pid) {
            if !trimmedTitle.isEmpty, focusedTitle == trimmedTitle { return true }
            if !trimmedDisplay.isEmpty, focusedTitle == trimmedDisplay { return true }
            for title in WindowFocusHelper.titlesForScript(windowTitle: windowTitle, displayTitle: displayTitle) {
                if focusedTitle == title { return true }
            }
        }

        if windowID != 0,
           let frontID = WindowFocusHelper.focusedWindowID(pid: pid),
           frontID == windowID {
            return true
        }

        return trimmedTitle.isEmpty && windowID == 0
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
