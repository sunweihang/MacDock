import AppKit
import CoreGraphics

enum WindowVisibilityFilter {
    /// Electron 等会多出无意义 AX 窗（如水印层），不应出现在切换列表
    private static let auxiliaryTitleSubstrings = [
        "watermark",
        "watermarkwidget",
    ]

    static func shouldInclude(_ window: EnumeratedWindow, bundleId: String?) -> Bool {
        if isAuxiliaryWindow(window) {
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

    private static func isAuxiliaryWindow(_ window: EnumeratedWindow) -> Bool {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !title.isEmpty else { return false }
        return auxiliaryTitleSubstrings.contains { title.contains($0) }
    }
}
