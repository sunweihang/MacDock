import AppKit
import ApplicationServices

/// 仅在被用户明确请求时，尝试让前台窗口退出 macOS 原生全屏以恢复标题栏。
@MainActor
enum WindowTitleBarRecovery {
    @discardableResult
    static func exitNativeFullscreenForFrontmostApp() -> Bool {
        guard AccessibilityTrust.queryWithoutPrompt(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let window = WindowFocusHelper.focusedWindowElement(pid: app.processIdentifier) else {
            return false
        }

        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success,
              (ref as? NSNumber)?.boolValue == true else {
            return false
        }

        return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) == .success
    }
}
