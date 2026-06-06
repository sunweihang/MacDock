import AppKit
import CoreGraphics

struct RunningWindowItem: Identifiable, Equatable {
    let windowID: CGWindowID
    let bundleIdentifier: String
    let appName: String
    let windowTitle: String
    /// 系统/自动生成的标题
    let defaultTitle: String
    /// 展示名（含自定义别名）
    let displayTitle: String
    /// 自定义名称持久化键
    let aliasKey: String
    let bounds: CGRect
    let icon: NSImage
    let pid: pid_t

    var id: String { "\(pid)-\(windowID)" }

    static func == (lhs: RunningWindowItem, rhs: RunningWindowItem) -> Bool {
        lhs.id == rhs.id
    }
}
