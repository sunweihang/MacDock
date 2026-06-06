import AppKit

@MainActor
enum AppLauncher {
    static func icon(forBundleIdentifier bundleId: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 32, height: 32))
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func displayName(forBundleIdentifier bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: url) else {
            return bundleId
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleId
    }

    /// 与系统程序坞一致：左键一律 openApplication(activates: true)；右键「显示全部窗口」才 activateAllWindows。
    static func activatePinned(bundleIdentifier: String, showAllWindows: Bool = false) {
        if showAllWindows,
           let app = runningApplication(forBundleIdentifier: bundleIdentifier) {
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func runningApplication(forBundleIdentifier bundleId: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleId && !$0.isTerminated
        }
    }
}
