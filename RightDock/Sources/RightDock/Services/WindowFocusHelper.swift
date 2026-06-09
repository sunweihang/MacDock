import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum WindowFocusHelper {
    static func isTrusted() -> Bool {
        AccessibilityTrust.isGranted
    }

    static func isTrustedNow() -> Bool {
        AccessibilityTrust.queryWithoutPrompt()
    }

    static func checkAccessibilitySilently() {
        _ = AccessibilityTrust.queryWithoutPrompt()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }

    static var runningExecutablePath: String {
        Bundle.main.bundleURL.path
    }

    static func frontmostWindowID() -> CGWindowID? {
        guard isTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return windowID(forFocusedWindowOf: front.processIdentifier)
    }

    static func frontmostWindowTitle() -> String? {
        guard isTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return focusedWindowTitle(pid: front.processIdentifier)
    }

    static func focus(
        windowID targetWindowID: CGWindowID,
        pid: pid_t,
        bounds: CGRect,
        windowTitle: String,
        displayTitle: String
    ) {
        _ = AccessibilityTrust.refreshForUserAction()
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let bundleId = app.bundleIdentifier ?? ""

        WindowActivation.focusWindow(
            windowID: targetWindowID,
            pid: pid,
            bounds: bounds,
            windowTitle: windowTitle,
            displayTitle: displayTitle,
            bundleIdentifier: bundleId.isEmpty ? nil : bundleId
        )

        if WindowActivation.focusMatchesWindow(
            pid: pid,
            windowID: targetWindowID,
            windowTitle: windowTitle,
            displayTitle: displayTitle
        ) {
            return
        }

        activateRunningApplication(
            pid: pid,
            bundleIdentifier: bundleId,
            restoreMinimized: true
        )
    }

    /// 按 Bundle ID 置前已运行应用（供 AppleScript 路径回退）
    @discardableResult
    static func activateRunningApplication(
        bundleIdentifier: String?,
        restoreMinimized: Bool
    ) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
              }) else {
            return false
        }
        activateRunningApplication(
            pid: app.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            restoreMinimized: restoreMinimized
        )
        return WindowActivation.verifyFrontmost(pid: app.processIdentifier)
    }

    /// 应用级置前（恢复最小化、System Events 无窗口时仍可用）
    static func activateRunningApplication(
        pid: pid_t,
        bundleIdentifier: String,
        restoreMinimized: Bool
    ) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.isHidden {
                app.unhide()
            }
            var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
            if restoreMinimized {
                options.insert(.activateAllWindows)
            }
            app.activate(options: options)
            if WindowActivation.verifyFrontmost(pid: pid) {
                return
            }
        }

        if !bundleIdentifier.isEmpty {
            AppLauncher.activatePinned(
                bundleIdentifier: bundleIdentifier,
                showAllWindows: restoreMinimized
            )
        }
    }

    static func titlesForScript(windowTitle: String, displayTitle: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [windowTitle, displayTitle] {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t).inserted else { continue }
            result.append(t)
            if let suffix = titleSuffixAfterAppSeparator(t), seen.insert(suffix).inserted {
                result.append(suffix)
            }
        }
        return result
    }

    /// `Fork — ZombieGunRun` → 也尝试 `ZombieGunRun`
    private static func titleSuffixAfterAppSeparator(_ title: String) -> String? {
        let separators = [" — ", " - ", " – "]
        for sep in separators where title.contains(sep) {
            let parts = title.components(separatedBy: sep)
            if let last = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
                return last
            }
        }
        return nil
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        windowID(forFocusedWindowOf: pid)
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard let element = focusedWindowElement(pid: pid) else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func windowID(forFocusedWindowOf pid: pid_t) -> CGWindowID? {
        guard let element = focusedWindowElement(pid: pid) else { return nil }
        return PrivateAX.cgWindowID(for: element) ?? axWindowIDAttribute(from: element)
    }

    static func focusedWindowElement(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let element = focusedWindowRef,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        return (element as! AXUIElement)
    }

    /// 已停用：直接 AX 改最小化/置前会破坏各应用标题栏（Cursor 等）。
    static func raiseAXWindow(_ window: AXUIElement, pid: pid_t, bundleIdentifier: String? = nil) {
        _ = window
        _ = pid
        _ = bundleIdentifier
    }

    private static func axWindowIDAttribute(from element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowID" as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }
}
