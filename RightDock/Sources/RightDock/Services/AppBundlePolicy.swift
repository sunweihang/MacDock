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
        "com.electron.",
        "com.cocos.creator",
    ]

    /// 不宜由 RightDock 自动改窗口尺寸（Cocos 等 Electron 应用会丢窗或错位）
    private static let layoutExemptPrefixes = [
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
        return id.contains("electron")
    }

    static func shouldSkipLayoutEnforcement(bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        return layoutExemptPrefixes.contains { id.hasPrefix($0.lowercased()) }
    }

}
