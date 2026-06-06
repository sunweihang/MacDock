import AppKit
import ApplicationServices

/// Cursor / Electron：用 System Events 调窗口几何，避免直接 AX 改最小化/置前。
enum ElectronWindowLayout {
    @discardableResult
    static func applyFrame(
        processName: String,
        screenRectBottomLeftOrigin rect: CGRect
    ) -> Bool {
        let process = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !process.isEmpty else { return false }

        let ax = WindowBoundsMatcher.axFrame(fromScreenBoundsBottomLeft: rect)
        let x = Int(ax.origin.x.rounded())
        let y = Int(ax.origin.y.rounded())
        let w = Int(ax.width.rounded())
        let h = Int(ax.height.rounded())
        guard w >= 200, h >= 200 else { return false }

        let source = """
        tell application "System Events"
            if not (exists process "\(process.appleScriptEscaped)") then
                return "missing"
            end if
            tell process "\(process.appleScriptEscaped)"
                set frontmost to true
                if (count of windows) is 0 then
                    return "missing"
                end if
                try
                    tell front window
                        set position to {\(x), \(y)}
                        set size to {\(w), \(h)}
                    end tell
                    return "ok"
                end try
            end tell
        end tell
        return "missing"
        """

        return runAppleScript(source) == "ok"
    }

    /// 仅当窗口处于 macOS 原生全屏时，用快捷键退出（比直接写 AXFullScreen 更安全）。
    @discardableResult
    static func exitNativeFullscreen(processName: String) -> Bool {
        let process = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !process.isEmpty else { return false }

        let source = """
        tell application "System Events"
            if not (exists process "\(process.appleScriptEscaped)") then
                return "missing"
            end if
            tell process "\(process.appleScriptEscaped)"
                set frontmost to true
                keystroke "f" using {control down, command down}
                return "ok"
            end tell
        end tell
        """

        return runAppleScript(source) == "ok"
    }

    static func processName(for app: NSRunningApplication) -> String? {
        let candidates = [
            app.localizedName,
            app.bundleURL?.deletingPathExtension().lastPathComponent,
        ]
        for raw in candidates {
            let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
