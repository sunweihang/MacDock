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
    static func collectWindows(
        accessibilityGranted: Bool,
        allowedPids: Set<pid_t>,
        bundleIdForPid: (pid_t) -> String?
    ) -> [EnumeratedWindow] {
        let onScreen = onScreenWindows()
        let minimized = accessibilityGranted ? minimizedWindows(forPids: allowedPids) : []
        var result: [EnumeratedWindow] = []

        for pid in allowedPids {
            let bundleId = bundleIdForPid(pid) ?? ""
            var pidWindows: [EnumeratedWindow] = []
            var usedCgFallback = false

            if accessibilityGranted {
                if AppBundlePolicy.isElectron(bundleIdentifier: bundleId) {
                    pidWindows = electronWindows(
                        forPid: pid,
                        bundleId: bundleId,
                        onScreen: onScreen,
                        minimized: minimized
                    )
                } else {
                    pidWindows = axWindows(forPid: pid)
                }
            }

            if pidWindows.isEmpty {
                let cgOn = onScreen.filter { $0.pid == pid }
                let cgMin = minimized.filter { $0.pid == pid }
                pidWindows = merge(onScreen: cgOn, minimized: cgMin)
                if pidWindows.isEmpty, !AppBundlePolicy.isElectron(bundleIdentifier: bundleId) {
                    // Fork 等最小化时 AX 无标准窗，需用全量 CG 列表（Electron 跳过，避免关闭后幽灵窗）
                    pidWindows = cgWindows(forPid: pid)
                    usedCgFallback = true
                }
            }

            if usedCgFallback, AppBundlePolicy.shouldStripCgTitlesBeforeDedupe(bundleIdentifier: bundleId) {
                pidWindows = pidWindows.map {
                    EnumeratedWindow(
                        windowID: $0.windowID,
                        pid: $0.pid,
                        title: "",
                        bounds: $0.bounds,
                        layer: $0.layer
                    )
                }
            }

            pidWindows = dedupeOverlappingByFrame(pidWindows)
            pidWindows = dedupeSameSizeEmptyTitles(pidWindows)
            pidWindows = filterReachableWindows(
                pidWindows,
                onScreen: onScreen,
                accessibilityGranted: accessibilityGranted,
                bundleId: bundleId
            )
            result.append(contentsOf: pidWindows.map(supplementTitleFromAX))
        }
        return result
    }

    /// Electron：AX 常把占位层也注册为标准窗，需与 CG 几何交叉验证
    private static func electronWindows(
        forPid pid: pid_t,
        bundleId: String,
        onScreen: [EnumeratedWindow],
        minimized: [EnumeratedWindow]
    ) -> [EnumeratedWindow] {
        let ax = axWindows(forPid: pid)
        let cgMerged = merge(
            onScreen: onScreen.filter { $0.pid == pid },
            minimized: minimized.filter { $0.pid == pid }
        )
        let cgByID = Dictionary(
            uniqueKeysWithValues: cgMerged.filter { $0.windowID != 0 }.map { ($0.windowID, $0) }
        )

        var result: [EnumeratedWindow] = []

        for window in ax {
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                result.append(window)
                continue
            }

            let bounds = window.windowID != 0 ? (cgByID[window.windowID]?.bounds ?? window.bounds) : window.bounds
            guard WindowVisibilityFilter.isRealMainWindowGeometry(bounds, bundleId: bundleId) else { continue }
            result.append(EnumeratedWindow(
                windowID: window.windowID,
                pid: window.pid,
                title: window.title,
                bounds: bounds,
                layer: window.layer
            ))
        }

        if result.isEmpty {
            return cgMerged.filter {
                !$0.title.isEmpty || WindowVisibilityFilter.isRealMainWindowGeometry($0.bounds, bundleId: bundleId)
            }
        }

        let axIDs = Set(result.filter { $0.windowID != 0 }.map(\.windowID))
        for cg in cgMerged where !cg.title.isEmpty {
            if cg.windowID == 0 || !axIDs.contains(cg.windowID) {
                result.append(cg)
            }
        }
        return result
    }

    /// 同进程多个无标题、同尺寸 AX 重复项（飞书双 1337×859）只保留一个
    private static func dedupeSameSizeEmptyTitles(_ windows: [EnumeratedWindow]) -> [EnumeratedWindow] {
        var kept: [EnumeratedWindow] = []
        var seenEmptySizeKeys = Set<String>()

        for window in windows {
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                kept.append(window)
                continue
            }
            let key = "\(window.pid)|\(Int(window.bounds.width.rounded())),\(Int(window.bounds.height.rounded()))"
            guard seenEmptySizeKeys.insert(key).inserted else { continue }
            kept.append(window)
        }
        return kept
    }

    /// 保留屏幕内窗口与已最小化窗口；过滤关闭后残留的屏外 CG 幽灵窗
    private static func filterReachableWindows(
        _ windows: [EnumeratedWindow],
        onScreen: [EnumeratedWindow],
        accessibilityGranted: Bool,
        bundleId: String
    ) -> [EnumeratedWindow] {
        let onScreenIDs = Set(onScreen.filter { $0.windowID != 0 }.map(\.windowID))
        let forkMinimized = AppBundlePolicy.excludesAXDialogSubrole(bundleIdentifier: bundleId)
            && forkAppearsMinimized(pid: windows.first?.pid ?? 0)
        return windows.filter { window in
            isReachableWindow(
                window,
                onScreenIDs: onScreenIDs,
                accessibilityGranted: accessibilityGranted,
                treatAsMinimizedApp: forkMinimized
            )
        }
    }

    private static func isReachableWindow(
        _ window: EnumeratedWindow,
        onScreenIDs: Set<CGWindowID>,
        accessibilityGranted: Bool,
        treatAsMinimizedApp: Bool = false
    ) -> Bool {
        if window.windowID != 0, onScreenIDs.contains(window.windowID) {
            return true
        }

        guard accessibilityGranted else {
            return false
        }

        if isAXMinimized(window) {
            return true
        }

        // Fork 最小化：AX 标签页是 minimized AXDialog 且 windowID=0，与 CG 幽灵窗无法按 id 对应
        if treatAsMinimizedApp,
           WindowVisibilityFilter.isRealMainWindowGeometry(window.bounds, bundleId: bundleIdentifier(for: window.pid)) {
            return true
        }

        return false
    }

    /// Fork 最小化时没有标准 AX 窗，只剩 minimized AXDialog 标签页
    private static func forkAppearsMinimized(pid: pid_t) -> Bool {
        guard pid != 0,
              let bundleId = bundleIdentifier(for: pid),
              AppBundlePolicy.excludesAXDialogSubrole(bundleIdentifier: bundleId) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        var hasStandard = false
        var hasMinimizedDialog = false
        for axWindow in windows {
            guard isAXWindowRole(axWindow) else { continue }
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               subrole == kAXDialogSubrole as String {
                if isMinimized(axWindow) {
                    hasMinimizedDialog = true
                }
                continue
            }
            if isStandardWindow(axWindow, pid: pid) {
                hasStandard = true
            }
        }
        return !hasStandard && hasMinimizedDialog
    }

    private static func isAXWindowRole(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String,
              role == kAXWindowRole as String else {
            return false
        }
        return true
    }

    private static func isAXMinimized(_ window: EnumeratedWindow) -> Bool {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        for axWindow in windows {
            guard isStandardWindow(axWindow, pid: window.pid) else { continue }
            let windowID = PrivateAX.cgWindowID(for: axWindow) ?? axWindowID(from: axWindow) ?? 0
            if window.windowID != 0, windowID != window.windowID { continue }

            if window.windowID == 0 {
                let title = axTitle(from: axWindow)
                if title != window.title.trimmingCharacters(in: .whitespacesAndNewlines) { continue }
            }

            return isMinimized(axWindow)
        }
        return false
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
            guard isStandardWindow(axWindow, pid: pid) else { return nil }
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
            guard isStandardWindow(axWindow, pid: pid), isMinimized(axWindow) else { return nil }

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

    private static func isStandardWindow(_ window: AXUIElement, pid: pid_t) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String,
              role == kAXWindowRole as String else {
            return false
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            if subrole == kAXFloatingWindowSubrole as String {
                return false
            }
            if subrole == kAXDialogSubrole as String {
                // Fork 仓库标签在应用最小化后仍是 AXDialog；Firefox 最小化后主窗口会变成 AXDialog
                if let bundleId = bundleIdentifier(for: pid),
                   AppBundlePolicy.excludesAXDialogSubrole(bundleIdentifier: bundleId) {
                    return false
                }
                return isMinimized(window)
            }
        }
        return true
    }

    private static func bundleIdentifier(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// 同一进程、相同几何位置的 CG 幽灵窗（Fork 多标签）合并为一个
    private static func dedupeOverlappingByFrame(_ windows: [EnumeratedWindow]) -> [EnumeratedWindow] {
        var byFrame: [String: EnumeratedWindow] = [:]
        var withoutFrame: [EnumeratedWindow] = []

        for window in windows {
            let key = frameDedupeKey(window)
            if key.isEmpty {
                withoutFrame.append(window)
                continue
            }
            if let existing = byFrame[key] {
                byFrame[key] = pickRepresentative(existing, window)
            } else {
                byFrame[key] = window
            }
        }

        return Array(byFrame.values) + withoutFrame
    }

    /// Fork 等同几何幽灵窗（常无标题）合并；有标题的独立窗口（Cursor 多窗同尺寸）保留
    private static func frameDedupeKey(_ window: EnumeratedWindow) -> String {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let frame = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(Int(bounds.width)),\(Int(bounds.height))"
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return frame }
        return "\(frame)|\(title)"
    }

    private static func pickRepresentative(_ a: EnumeratedWindow, _ b: EnumeratedWindow) -> EnumeratedWindow {
        let aTitle = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bTitle = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if aTitle.isEmpty != bTitle.isEmpty {
            return aTitle.isEmpty ? b : a
        }
        return a.windowID >= b.windowID ? a : b
    }

    /// CG 窗口常无标题；Fork 等可从 AX 前台/主窗口取当前标签名
    private static func supplementTitleFromAX(_ window: EnumeratedWindow) -> EnumeratedWindow {
        guard window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return window }

        let appElement = AXUIElementCreateApplication(window.pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] as [CFString] {
            var windowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute, &windowRef) == .success,
                  let ref = windowRef,
                  CFGetTypeID(ref) == AXUIElementGetTypeID() else {
                continue
            }
            let axWindow = ref as! AXUIElement
            let axID = PrivateAX.cgWindowID(for: axWindow) ?? axWindowID(from: axWindow) ?? 0
            if window.windowID != 0, axID != window.windowID { continue }
            let title = axTitle(from: axWindow)
            guard !title.isEmpty else { continue }
            return EnumeratedWindow(
                windowID: window.windowID,
                pid: window.pid,
                title: title,
                bounds: window.bounds,
                layer: window.layer
            )
        }
        return window
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
