import CoreGraphics

/// 用于持久化自定义名称的稳定键
enum WindowAliasKey {
    static func make(
        bundleIdentifier: String,
        windowTitle: String,
        windowID: CGWindowID,
        duplicateIndex: Int
    ) -> String {
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return "\(bundleIdentifier)|app|\(windowID)"
        }
        if duplicateIndex > 1 {
            return "\(bundleIdentifier)|\(title)|\(duplicateIndex)"
        }
        return "\(bundleIdentifier)|\(title)"
    }
}
