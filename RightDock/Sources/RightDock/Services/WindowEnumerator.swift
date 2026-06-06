import AppKit
import ApplicationServices
import CoreGraphics

struct EnumeratedWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
    let layer: Int
}

enum WindowEnumerator {
    private static let minWindowDimension: CGFloat = 80

    static func onScreenWindows() -> [EnumeratedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { parse($0) }
    }

    /// 含最小化/屏外窗口（飞书、Firefox 等主进程无 AX 窗口列表时用）
    static func cgWindows(forPid pid: pid_t) -> [EnumeratedWindow] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { parse($0) }.filter { $0.pid == pid }
    }

    /// 已授权时优先用 AX 列窗口，避免 Cocos 等产生大量无标题 CG 幽灵窗口导致无法切换
    static func collectWindows(accessibilityGranted: Bool, allowedPids: Set<pid_t>) -> [EnumeratedWindow] {
        let onScreen = onScreenWindows()
        let minimized = accessibilityGranted ? minimizedWindows(forPids: allowedPids) : []
        var result: [EnumeratedWindow] = []

        for pid in allowedPids {
            if accessibilityGranted {
                let ax = axWindows(forPid: pid)
                if !ax.isEmpty {
                    result.append(contentsOf: ax)
                    continue
                }
            }
            let cgOn = onScreen.filter { $0.pid == pid }
            let cgMin = minimized.filter { $0.pid == pid }
            result.append(contentsOf: merge(onScreen: cgOn, minimized: cgMin))
        }
        return result
    }

    /// 辅助功能可见的全部标准窗口（含最小化）
    static func axWindows(forPid pid: pid_t) -> [EnumeratedWindow] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { axWindow in
            guard isStandardWindow(axWindow) else { return nil }
            let title = axTitle(from: axWindow)
            let windowID = PrivateAX.cgWindowID(for: axWindow) ?? axWindowID(from: axWindow) ?? 0
            let bounds = WindowBoundsMatcher.axFrame(of: axWindow) ?? .zero
            return EnumeratedWindow(
                windowID: windowID,
                pid: pid,
                title: title,
                bounds: bounds,
                layer: 0
            )
        }
    }

    /// 通过辅助功能枚举已最小化、不会出现在 CG 屏幕窗口列表中的窗口
    static func minimizedWindows(forPids pids: Set<pid_t>) -> [EnumeratedWindow] {
        pids.flatMap { minimizedWindows(forPid: $0) }
    }

    /// 合并屏幕内窗口与最小化窗口（按 windowID / pid+title 去重）
    static func merge(onScreen: [EnumeratedWindow], minimized: [EnumeratedWindow]) -> [EnumeratedWindow] {
        var result = onScreen
        var existingIDs = Set(onScreen.filter { $0.windowID != 0 }.map(\.windowID))
        var existingKeys = Set(onScreen.filter { $0.windowID == 0 }.map { dedupeKey(pid: $0.pid, title: $0.title) })

        for window in minimized {
            if window.windowID != 0 {
                guard existingIDs.insert(window.windowID).inserted else { continue }
            } else {
                let key = dedupeKey(pid: window.pid, title: window.title)
                guard existingKeys.insert(key).inserted else { continue }
            }
            result.append(window)
        }
        return result
    }

    private static func dedupeKey(pid: pid_t, title: String) -> String {
        "\(pid)|\(title)"
    }

    private static func minimizedWindows(forPid pid: pid_t) -> [EnumeratedWindow] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { axWindow in
            guard isStandardWindow(axWindow), isMinimized(axWindow) else { return nil }

            let title = axTitle(from: axWindow)
            let windowID = PrivateAX.cgWindowID(for: axWindow) ?? axWindowID(from: axWindow) ?? 0
            let bounds = WindowBoundsMatcher.axFrame(of: axWindow) ?? .zero

            return EnumeratedWindow(
                windowID: windowID,
                pid: pid,
                title: title,
                bounds: bounds,
                layer: 0
            )
        }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
              let minimized = minimizedRef as? Bool else {
            return false
        }
        return minimized
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String,
              role == kAXWindowRole as String else {
            return false
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            let excluded: Set<String> = [kAXFloatingWindowSubrole as String]
            return !excluded.contains(subrole)
        }
        return true
    }

    private static func axTitle(from element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return ""
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func axWindowID(from element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowID" as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }

    private static func parse(_ dict: [String: Any]) -> EnumeratedWindow? {
        guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
              let pid = dict[kCGWindowOwnerPID as String] as? Int32,
              let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
              let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let w = boundsDict["Width"], let h = boundsDict["Height"] else {
            return nil
        }

        let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0.05, w >= minWindowDimension, h >= minWindowDimension else { return nil }

        let title = (dict[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = dict[kCGWindowOwnerName as String] as? String ?? ""

        if owner == "Window Server" || owner == "Dock" || owner == "RightDock" {
            return nil
        }

        return EnumeratedWindow(
            windowID: windowID,
            pid: pid_t(pid),
            title: title,
            bounds: CGRect(x: x, y: y, width: w, height: h),
            layer: layer
        )
    }
}
