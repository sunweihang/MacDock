import AppKit

/// 点击 Dock 后释放面板焦点，不把 RightDock 再置顶（否则会挡住刚激活的应用）。
@MainActor
enum DockFocusYield {
    weak static var panel: NSPanel?

    static func prepareForExternalActivation() {
        panel?.resignKey()
    }

    static func finishExternalActivation(pid: pid_t, succeeded: Bool) {
        _ = pid
        _ = succeeded
        panel?.resignKey()
    }
}
