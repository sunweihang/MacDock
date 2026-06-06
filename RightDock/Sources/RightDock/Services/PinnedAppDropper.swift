import AppKit

@MainActor
enum PinnedAppDropper {
    @discardableResult
    static func addApplications(from pasteboard: NSPasteboard, settings: DockSettings) -> Bool {
        let urls = AppDropPasteboard.applicationURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }

        var added = false
        for url in urls {
            guard let app = AppDropResolver.resolveAppURL(url) else { continue }
            settings.addPinned(bundleIdentifier: app.bundleIdentifier, displayName: app.displayName)
            added = true
        }
        return added
    }
}
