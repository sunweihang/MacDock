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
