import AppKit
import Foundation

/// 通过 System Events 切换窗口（对 Cursor / Electron / 浏览器更稳定）
@MainActor
enum WindowFocusScript {
    @discardableResult
    static func focus(processName: String, windowTitle: String) -> Bool {
        let process = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !process.isEmpty, !title.isEmpty else { return false }

        let source = """
        tell application "System Events"
            tell process "\(process.appleScriptEscaped)"
                set frontmost to true
                repeat with w in windows
                    set wName to name of w
                    if wName is "\(title.appleScriptEscaped)" or wName contains "\(title.appleScriptEscaped)" or "\(title.appleScriptEscaped)" contains wName then
                        try
                            perform action "AXRaise" of w
                        end try
                        return "ok"
                    end if
                end repeat
            end tell
        end tell
        return "missing"
        """

        return runAppleScript(source) == "ok"
    }

    /// 按 CGWindowID 切换（同应用多窗口时比标题更稳定）
    @discardableResult
    static func focus(processName: String, windowID: CGWindowID) -> Bool {
        let process = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !process.isEmpty, windowID != 0 else { return false }

        let source = """
        tell application "System Events"
            tell process "\(process.appleScriptEscaped)"
                set frontmost to true
                repeat with w in windows
                    try
                        if (value of attribute "AXWindowID" of w) is \(windowID) then
                            perform action "AXRaise" of w
                            return "ok"
                        end if
                    end try
                end repeat
            end tell
        end tell
        return "missing"
        """

        return runAppleScript(source) == "ok"
    }

    /// 固定区：按进程名置前窗口（不依赖窗口标题）
    @discardableResult
    static func activateProcess(
        processName: String,
        bundleIdentifier: String? = nil,
        allWindows: Bool = false
    ) -> Bool {
        let process = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !process.isEmpty else { return false }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let byBundle = """
            try
                tell application id "\(bundleIdentifier.appleScriptEscaped)" to activate
            end try
            """
            _ = runAppleScript(byBundle)
        }

        let source: String
        if allWindows {
            source = """
            tell application "System Events"
                tell process "\(process.appleScriptEscaped)"
                    set frontmost to true
                    repeat with w in windows
                        try
                            perform action "AXRaise" of w
                        end try
                    end repeat
                    return "ok"
                end tell
            end tell
            """
        } else {
            source = """
            tell application "System Events"
                if not (exists process "\(process.appleScriptEscaped)") then
                    return "missing"
                end if
                tell process "\(process.appleScriptEscaped)"
                    set frontmost to true
                    repeat with w in windows
                        try
                            set isMin to value of attribute "AXMinimized" of w
                        on error
                            set isMin to false
                        end try
                        if isMin is false then
                            perform action "AXRaise" of w
                            return "ok"
                        end if
                    end repeat
                    repeat with w in windows
                        try
                            perform action "AXRaise" of w
                            return "ok"
                        end try
                    end repeat
                end tell
            end tell
            return "missing"
            """
        }

        if runAppleScript(source) == "ok" {
            return true
        }

        return WindowFocusHelper.activateRunningApplication(
            bundleIdentifier: bundleIdentifier,
            restoreMinimized: allWindows
        )
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
