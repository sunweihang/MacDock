import ApplicationServices
import AppKit
import Foundation

/// 辅助功能授权：系统 API 在 ad-hoc 签名下常误报未授权，故结合真实 AX 探测。
@MainActor
enum AccessibilityTrust {
    private static var cachedGranted: Bool?
    private static var lastGrantedCheck = Date.distantPast
    private static let grantedRecheckInterval: TimeInterval = 15

    private static var cachedAutomationGranted: Bool?
    private static var lastAutomationCheck = Date.distantPast
    private static let automationRecheckInterval: TimeInterval = 60

    static var isGranted: Bool {
        if let cachedGranted, cachedGranted,
           Date().timeIntervalSince(lastGrantedCheck) < grantedRecheckInterval {
            return true
        }
        return refreshForUserAction()
    }

    @discardableResult
    static func refreshForUserAction() -> Bool {
        let granted = queryWithoutPrompt()
        if granted {
            cachedGranted = true
            lastGrantedCheck = Date()
        } else {
            cachedGranted = nil
            lastGrantedCheck = .distantPast
        }
        return granted
    }

    static func invalidateCache() {
        cachedGranted = nil
        lastGrantedCheck = .distantPast
        cachedAutomationGranted = nil
        lastAutomationCheck = .distantPast
    }

    private static let promptAttemptKey = "accessibilityPromptAttempted"

    /// 未授权时弹出系统「辅助功能访问」对话框并打开系统设置（仅自动尝试一次）
    /// 触发「自动化 / 控制 System Events」授权（切换 Cursor 窗口需要）
    static func warmupAutomationAccess() {
        let source = "tell application \"System Events\" to return 1"
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
    }

    /// 启动时静默探测授权状态，不弹系统对话框、不打开系统设置、不触发自动化授权。
    static func prepareOnLaunch() {
        if queryWithoutPrompt() {
            cachedGranted = true
            lastGrantedCheck = Date()
        }
    }

    /// 用户主动请求授权（菜单「重新请求辅助功能授权」）；启动时请用 prepareOnLaunch。
    static func requestAuthorizationIfNeeded() {
        warmupAutomationAccess()
        guard !queryWithoutPrompt() else { return }
        guard !UserDefaults.standard.bool(forKey: promptAttemptKey) else { return }
        UserDefaults.standard.set(true, forKey: promptAttemptKey)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 菜单栏：辅助功能状态（与自动化分开显示）
    static var statusMessage: String {
        if queryWithoutPrompt() {
            return "辅助功能：已生效 ✓"
        }
        return "辅助功能：未生效 — 请删除后重新添加 RightDock"
    }

    /// 菜单栏：自动化 / System Events 状态（始终单独一行）
    static var automationStatusMessage: String {
        if automationIsGranted() {
            return "自动化：已允许控制 System Events ✓"
        }
        return "自动化：未允许 — 需在隐私里允许 RightDock 控制 System Events"
    }

    /// 能否通过 System Events 读取并操作其他应用窗口（隐私 → 自动化）
    static func automationIsGranted() -> Bool {
        if let cachedAutomationGranted,
           Date().timeIntervalSince(lastAutomationCheck) < automationRecheckInterval {
            return cachedAutomationGranted
        }
        let granted = probeAutomationControl()
        cachedAutomationGranted = granted
        lastAutomationCheck = Date()
        return granted
    }

    static func probeAutomationControl() -> Bool {
        let source = """
        tell application "System Events"
            repeat with proc in application processes
                if background only of proc is false then
                    try
                        if (count of windows of proc) ≥ 0 then
                            return "ok"
                        end if
                    end try
                end if
            end repeat
        end tell
        return "denied"
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        return error == nil && result.stringValue == "ok"
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 系统开关 + 实际能否读取其他应用窗口
    static func queryWithoutPrompt() -> Bool {
        if axIsProcessTrusted() {
            return true
        }
        return probeCanReadOtherAppWindows()
    }

    private static func axIsProcessTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 实际尝试读取多个前台应用的窗口（比单测 AXIsProcessTrusted 更可靠）
    private static func probeCanReadOtherAppWindows() -> Bool {
        let ownBundle = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.bundleIdentifier != ownBundle,
                  app.bundleIdentifier != nil else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success {
                return true
            }
        }
        return false
    }

    /// 供菜单「重新请求授权」调用
    static func resetAndRequestAuthorization() {
        UserDefaults.standard.removeObject(forKey: promptAttemptKey)
        invalidateCache()
        requestAuthorizationIfNeeded()
    }
}
