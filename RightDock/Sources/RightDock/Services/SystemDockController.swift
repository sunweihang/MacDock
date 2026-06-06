import AppKit
import Foundation

/// 用系统 Dock 在屏幕右侧常驻占位（autohide 关闭），让 `visibleFrame` 右边界与 RightDock 左缘对齐。
/// 退出 / 隐藏 RightDock 时必须恢复系统程序坞，避免右侧残留细条。
enum SystemDockController {
    private static let backupKey = "systemDockPreferencesBackupV2"
    private static let legacyBackupKey = "systemDockPreferencesBackup"

    private(set) static var reservesRightEdgeForFullscreen = false
    private static var didRestoreDockOnExit = false

    private static var pendingSync: DispatchWorkItem?
    private static var pendingCalibration: DispatchWorkItem?
    private static var lastCalibrationMeasured: CGFloat?

    private struct Backup: Codable {
        let autohide: Bool
        let autohideDelay: Double
        let autohideTimeModifier: Double
        let orientation: String
        let tilesize: Int
        let largesize: Int?
    }

    /// 替换系统 Dock：右侧常驻占位 + RightDock 覆盖显示
    static func activateReplacement(reservedWidth: CGFloat) {
        didRestoreDockOnExit = false
        if readBackup() == nil {
            saveBackup(sanitizedBackupFromCurrentDock())
        }

        reservesRightEdgeForFullscreen = true
        applyReserveScript(width: reservedWidth)
        scheduleCalibration(targetWidth: reservedWidth, delay: 0.5)
    }

    /// 多屏时系统 Dock 可能被还原为底部；仅当 RightDock 在主屏时才同步系统占位。
    @MainActor
    static func ensureReplacementActive(reservedWidth: CGFloat) {
        guard DockScreenLayout.shouldSyncSystemDockReservation() else { return }

        guard readBackup() != nil else {
            activateReplacement(reservedWidth: reservedWidth)
            return
        }
        let orientation = readDockString("orientation") ?? "bottom"
        if orientation != "right" || !reservesRightEdgeForFullscreen {
            reservesRightEdgeForFullscreen = true
            applyReserveScript(width: reservedWidth)
            scheduleCalibration(targetWidth: reservedWidth, delay: 0.35)
        }
    }

    /// 隐藏 RightDock 面板时临时恢复系统程序坞（保留备份，再次显示时可继续替换）
    static func pauseReplacement() {
        stopReplacementWork()
        _ = applyBackupToDock(clearBackupAfter: false)
    }

    /// 退出 RightDock：恢复系统程序坞并清除备份
    static func restoreSystemDock() {
        guard !didRestoreDockOnExit else { return }
        didRestoreDockOnExit = true
        stopReplacementWork()

        if readBackup() != nil {
            let restored = applyBackupToDock(clearBackupAfter: true)
            if !restored {
                // 退出时 shell 偶发失败：再试一次，避免右侧细条残留
                _ = applyBackupToDock(clearBackupAfter: true)
            }
            return
        }

        // 无备份时仅清理 RightDock 遗留的右侧细条，不覆盖用户当前 Dock 偏好
        _ = repairStuckRightReplacementDock()
    }

    /// 菜单「恢复系统程序坞」：强制回到底部默认
    static func forceResetToStandardDock() {
        stopReplacementWork()
        clearBackup()
        clearLegacyBackup()
        _ = applyStandardBottomDock()
    }

    private static func stopReplacementWork() {
        reservesRightEdgeForFullscreen = false
        pendingSync?.cancel()
        pendingCalibration?.cancel()
        pendingSync = nil
        pendingCalibration = nil
        lastCalibrationMeasured = nil
    }

    /// 用户调节宽度后延迟同步，避免拖拽过程中反复 killall Dock
    @MainActor
    static func scheduleReservedWidthSync(_ reservedWidth: CGFloat) {
        guard DockScreenLayout.shouldSyncSystemDockReservation() else { return }
        guard reservesRightEdgeForFullscreen, readBackup() != nil else { return }
        pendingSync?.cancel()
        let work = DispatchWorkItem {
            applyReserveScript(width: reservedWidth)
            scheduleCalibration(targetWidth: reservedWidth, delay: 0.7)
        }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func scheduleCalibration(targetWidth: CGFloat, delay: TimeInterval = 0.35, attempt: Int = 0) {
        guard reservesRightEdgeForFullscreen, attempt < 8 else { return }
        pendingCalibration?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                let done = calibrateReservedWidthIfNeeded(targetWidth: targetWidth, attempt: attempt)
                if !done, attempt + 1 < 8 {
                    scheduleCalibration(targetWidth: targetWidth, delay: 0.65, attempt: attempt + 1)
                }
            }
        }
        pendingCalibration = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @MainActor
    private static func calibrateReservedWidthIfNeeded(targetWidth: CGFloat, attempt: Int) -> Bool {
        guard reservesRightEdgeForFullscreen else { return true }
        guard DockScreenLayout.shouldSyncSystemDockReservation() else { return true }

        let screen = NSScreen.main ?? DockScreenLayout.hostScreen()
        let measured = DockScreenLayout.systemReservedWidth(on: screen)
        let target = targetWidth.rounded()
        let delta = target - measured

        if abs(delta) <= 1 {
            return true
        }

        if let lastCalibrationMeasured, abs(lastCalibrationMeasured - measured) < 0.5, abs(delta) > 4 {
            // 部分 macOS 版本右侧 visibleFrame 让出宽度不随 tilesize 继续增大
            return true
        }
        lastCalibrationMeasured = measured

        let currentTile = readDockInt("tilesize") ?? Int(target)
        let adjusted: Int
        if measured > 4, abs(delta) > 4 {
            let scale = target / measured
            adjusted = max(24, min(256, Int((CGFloat(currentTile) * scale).rounded())))
        } else {
            adjusted = max(24, min(256, currentTile + Int(delta.rounded())))
        }
        guard adjusted != currentTile else { return true }

        _ = runShell("""
        /usr/bin/defaults write com.apple.dock tilesize -int \(adjusted) && \
        /usr/bin/defaults write com.apple.dock largesize -int \(adjusted) && \
        /usr/bin/killall Dock 2>/dev/null || true
        """)

        return false
    }

    private static func applyReserveScript(width: CGFloat) {
        guard reservesRightEdgeForFullscreen else { return }
        let tile = max(24, min(256, Int(width.rounded())))
        _ = runShell("""
        /usr/bin/defaults write com.apple.dock orientation -string right && \
        /usr/bin/defaults write com.apple.dock autohide -bool false && \
        /usr/bin/defaults write com.apple.dock tilesize -int \(tile) && \
        /usr/bin/defaults write com.apple.dock largesize -int \(tile) && \
        /usr/bin/defaults write com.apple.dock magnification -bool false && \
        /usr/bin/killall Dock 2>/dev/null || true
        """)
    }

    @discardableResult
    private static func applyBackupToDock(clearBackupAfter: Bool) -> Bool {
        guard let backup = readBackup() else {
            return applyStandardBottomDock()
        }

        // 右侧占位是 RightDock 留下的状态，不能原样恢复
        let orientation = backup.orientation == "right" ? "bottom" : backup.orientation
        let restored = applyDockPreferences(
            orientation: orientation,
            autohide: backup.autohide,
            autohideDelay: backup.autohideDelay,
            autohideTimeModifier: backup.autohideTimeModifier,
            tilesize: backup.tilesize,
            largesize: backup.largesize
        )

        if restored, clearBackupAfter {
            clearBackup()
            clearLegacyBackup()
        }

        return restored
    }

    /// RightDock 退出异常或未留下备份时，系统 Dock 可能仍停在右侧大 tile 占位状态
    @discardableResult
    private static func repairStuckRightReplacementDock() -> Bool {
        let orientation = readDockString("orientation") ?? "bottom"
        let tile = readDockInt("tilesize") ?? 64
        guard orientation == "right", tile >= 72 else { return true }
        return applyStandardBottomDock()
    }

    @discardableResult
    private static func applyStandardBottomDock() -> Bool {
        applyDockPreferences(
            orientation: "bottom",
            autohide: true,
            autohideDelay: 0.5,
            autohideTimeModifier: 0.5,
            tilesize: 64,
            largesize: 128
        )
    }

    @discardableResult
    private static func applyDockPreferences(
        orientation: String,
        autohide: Bool,
        autohideDelay: Double,
        autohideTimeModifier: Double,
        tilesize: Int,
        largesize: Int?
    ) -> Bool {
        let autohideStr = autohide ? "true" : "false"
        var parts = [
            "/usr/bin/defaults write com.apple.dock orientation -string \(orientation)",
            "/usr/bin/defaults write com.apple.dock autohide -bool \(autohideStr)",
            "/usr/bin/defaults write com.apple.dock autohide-delay -float \(autohideDelay)",
            "/usr/bin/defaults write com.apple.dock autohide-time-modifier -float \(autohideTimeModifier)",
            "/usr/bin/defaults write com.apple.dock tilesize -int \(tilesize)",
            "/usr/bin/defaults delete com.apple.dock wvous-br-corner 2>/dev/null || true",
            "/usr/bin/defaults delete com.apple.dock wvous-bl-corner 2>/dev/null || true",
            "/usr/bin/defaults delete com.apple.dock wvous-tr-corner 2>/dev/null || true",
            "/usr/bin/defaults delete com.apple.dock wvous-tl-corner 2>/dev/null || true",
        ]
        if let largesize {
            parts.append("/usr/bin/defaults write com.apple.dock largesize -int \(largesize)")
        }
        parts.append("/usr/bin/killall Dock 2>/dev/null || true")
        return runShell(parts.joined(separator: " && "))
    }

    /// 若当前已是 RightDock 留下的右侧占位，则备份「底部默认」而非错误状态
    private static func sanitizedBackupFromCurrentDock() -> Backup {
        let orientation = readDockString("orientation") ?? "bottom"
        let tile = readDockInt("tilesize") ?? 64

        if orientation == "right", tile >= 72 {
            return Backup(
                autohide: false,
                autohideDelay: 0.5,
                autohideTimeModifier: 0.5,
                orientation: "bottom",
                tilesize: 64,
                largesize: 128
            )
        }

        return Backup(
            autohide: readDockBool("autohide") ?? false,
            autohideDelay: readDockDouble("autohide-delay") ?? 0.5,
            autohideTimeModifier: readDockDouble("autohide-time-modifier") ?? 0.5,
            orientation: orientation,
            tilesize: tile,
            largesize: readDockInt("largesize")
        )
    }

    private static func readDockString(_ key: String) -> String? {
        guard let raw = shellOutput("/usr/bin/defaults read com.apple.dock \(key) 2>/dev/null")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func readDockInt(_ key: String) -> Int? {
        guard let raw = readDockString(key) else { return nil }
        return Int(raw)
    }

    private static func readDockBool(_ key: String) -> Bool? {
        guard let raw = shellOutput("/usr/bin/defaults read com.apple.dock \(key) 2>/dev/null")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if raw == "1" || raw.lowercased() == "yes" || raw.lowercased() == "true" {
            return true
        }
        if raw == "0" || raw.lowercased() == "no" || raw.lowercased() == "false" {
            return false
        }
        return nil
    }

    private static func readDockDouble(_ key: String) -> Double? {
        guard let raw = shellOutput("/usr/bin/defaults read com.apple.dock \(key) 2>/dev/null")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return Double(raw)
    }

    @discardableResult
    private static func runShell(_ script: String) -> Bool {
        shellOutput(script) != nil
    }

    private static func shellOutput(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func readBackup() -> Backup? {
        guard let data = UserDefaults.standard.data(forKey: backupKey) else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: data)
    }

    private static func saveBackup(_ backup: Backup) {
        guard let data = try? JSONEncoder().encode(backup) else { return }
        UserDefaults.standard.set(data, forKey: backupKey)
    }

    private static func clearBackup() {
        UserDefaults.standard.removeObject(forKey: backupKey)
    }

    private static func clearLegacyBackup() {
        UserDefaults.standard.removeObject(forKey: legacyBackupKey)
    }
}
