import AppKit

@MainActor
enum AppLauncher {
    static func icon(for pinned: PinnedApp) -> NSImage {
        if pinned.isTrashPin {
            return trashIcon()
        }
        if let path = pinned.folderPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return icon(forBundleIdentifier: pinned.bundleIdentifier)
    }

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

    static func activate(pinned: PinnedApp, showAllWindows: Bool = false) {
        if pinned.isTrashPin {
            openTrash()
            return
        }
        if let path = pinned.folderPath {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            NSWorkspace.shared.open(url)
            return
        }
        activatePinned(bundleIdentifier: pinned.bundleIdentifier, showAllWindows: showAllWindows)
    }

    private static func trashIcon() -> NSImage {
        if let icon = NSImage(named: NSImage.trashFullName) {
            return icon
        }
        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        return NSWorkspace.shared.icon(forFile: trashPath)
    }

    private static func openTrash() {
        let source = #"tell application "Finder" to open trash"#
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if error == nil { return }
        }
        let trashURL = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash"), isDirectory: true)
        NSWorkspace.shared.open(trashURL)
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
