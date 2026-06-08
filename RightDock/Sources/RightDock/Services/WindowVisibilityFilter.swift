import AppKit
import CoreGraphics

enum WindowVisibilityFilter {
    /// Electron 等会多出无意义 AX 窗（如水印层），不应出现在切换列表
    private static let auxiliaryTitleSubstrings = [
        "watermark",
        "watermarkwidget",
    ]

    /// 无标题占位窗常见尺寸（微信/飞书/飞连等 Electron 应用）
    private static let ghostEmptyTitleSizes: [(Int, Int)] = [
        (500, 500),
    ]

    private static let minRealWindowWidth: CGFloat = 360
    private static let minRealWindowHeight: CGFloat = 280

    static func shouldInclude(_ window: EnumeratedWindow, bundleId: String?) -> Bool {
        if isAuxiliaryWindow(window) {
            return false
        }

        if isGhostWindow(window, bundleId: bundleId) {
            return false
        }

        if window.title.isEmpty {
            // 过滤极小占位窗口；最小化时 bounds 可能为 0，仍保留
            let hasSize = window.bounds.width > 0 && window.bounds.height > 0
            if hasSize, window.bounds.width < 120 || window.bounds.height < 120 {
                return false
            }
        }

        return true
    }

    /// 无标题窗口是否具备可切换的主窗口尺寸（供枚举阶段复用）
    static func isRealMainWindowGeometry(_ bounds: CGRect, bundleId: String?) -> Bool {
        let w = bounds.width
        let h = bounds.height
        if w <= 0 || h <= 0 { return true }
        if matchesGhostSize(bounds) { return false }
        if let bundleId, AppBundlePolicy.isElectron(bundleIdentifier: bundleId) {
            return w >= minRealWindowWidth && h >= minRealWindowHeight
        }
        return w >= 120 && h >= 120
    }

    static func matchesGhostSize(_ bounds: CGRect) -> Bool {
        let w = Int(bounds.width.rounded())
        let h = Int(bounds.height.rounded())
        for (ghostW, ghostH) in ghostEmptyTitleSizes {
            if abs(w - ghostW) <= 2, abs(h - ghostH) <= 2 { return true }
        }
        return false
    }

    private static func isGhostWindow(_ window: EnumeratedWindow, bundleId: String?) -> Bool {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return false }

        let w = window.bounds.width
        let h = window.bounds.height
        guard w > 0, h > 0 else { return false }

        if matchesGhostSize(window.bounds) {
            return true
        }

        if let bundleId, AppBundlePolicy.isElectron(bundleIdentifier: bundleId) {
            if w < minRealWindowWidth || h < minRealWindowHeight {
                return true
            }
        }

        return false
    }

    private static func isAuxiliaryWindow(_ window: EnumeratedWindow) -> Bool {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !title.isEmpty else { return false }
        return auxiliaryTitleSubstrings.contains { title.contains($0) }
    }
}
