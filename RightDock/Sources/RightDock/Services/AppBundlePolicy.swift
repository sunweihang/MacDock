import Foundation

/// 不宜用 AX API 直接改窗口几何/最小化状态的应用（Electron 等会丢标题栏按钮）。
enum AppBundlePolicy {
    private static let axSensitivePrefix = [
        "com.todesktop.",
        "com.microsoft.VSCode",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.github.atom",
        "com.slack.Slack",
        "com.tencent.xinWeChat",
        "com.volcengine.corplink",
        "com.electron.",
        "com.cocos.creator",
    ]

    /// Fork 会把每个仓库标签注册为 AXDialog；应用最小化后这些标签仍可能带 minimized 标记，不能按 Firefox 规则保留。
    private static let axDialogAlwaysExcluded = [
        "com.DanPristupov.Fork",
    ]

    /// CG 回退时窗口名来自标签幽灵窗，去重前应清空以免按标题拆成多条。
    private static let stripsCgTitlesBeforeDedupe = axDialogAlwaysExcluded

    static func excludesAXDialogSubrole(bundleIdentifier: String) -> Bool {
        axDialogAlwaysExcluded.contains(bundleIdentifier)
    }

    static func shouldStripCgTitlesBeforeDedupe(bundleIdentifier: String) -> Bool {
        stripsCgTitlesBeforeDedupe.contains(bundleIdentifier)
    }

    /// 主窗口以 AXDialog 标签存在、CG/AX windowID 不可靠，需用 System Events 批量取消最小化。
    static func usesDialogRestoreActivation(bundleIdentifier: String) -> Bool {
        excludesAXDialogSubrole(bundleIdentifier: bundleIdentifier)
    }

    /// 辅助进程（小程序、Renderer 等）不应单独出现在窗口列表
    static func isHelperProcess(bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier
        if id.hasSuffix(".helper") { return true }
        if id.contains("WeChatAppEx") { return true }
        if id.contains("networkextension-wrapper") { return true }
        return false
    }

    /// Electron 应用改窗口几何时只缩宽度，避免直接写 position 导致丢窗或错位
    private static let widthOnlyLayoutPrefixes = [
        "com.cocos.",
    ]

    static func avoidsDirectAXWindowControl(bundleIdentifier: String) -> Bool {
        isElectron(bundleIdentifier: bundleIdentifier)
    }

    static func isElectron(bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        if axSensitivePrefix.contains(where: { id.hasPrefix($0.lowercased()) }) {
            return true
        }
        if widthOnlyLayoutPrefixes.contains(where: { id.hasPrefix($0.lowercased()) }) {
            return true
        }
        return id.contains("electron")
    }

    /// 仅调整窗口宽度（保留系统给出的位置与高度），用于 Cocos 等 Electron 应用。
    static func usesWidthOnlyLayoutAdjustment(bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        return widthOnlyLayoutPrefixes.contains { id.hasPrefix($0.lowercased()) }
    }

}
