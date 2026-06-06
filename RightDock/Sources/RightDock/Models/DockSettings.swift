import AppKit
import Combine
import SwiftUI

enum DockIconSize: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var dimension: CGFloat {
        switch self {
        case .small: 28
        case .medium: 36
        case .large: 44
        }
    }
}

struct PinnedApp: Identifiable, Codable, Equatable {
    let bundleIdentifier: String
    var displayName: String
    /// 若设置则点击时用访达打开该路径，而非启动应用。
    var folderPath: String?

    var id: String {
        if let folderPath { return "folder:\(folderPath)" }
        return bundleIdentifier
    }

    var isFolderPin: Bool { folderPath != nil }

    static let trashPinBundleIdentifier = "com.mactools.RightDock.trash-pin"

    var isTrashPin: Bool { bundleIdentifier == Self.trashPinBundleIdentifier }
}

@MainActor
final class DockSettings: ObservableObject {
    static let shared = DockSettings()

    static let barWidthMin: CGFloat = 72
    static let barWidthMax: CGFloat = 220
    static let barWidthDefault: CGFloat = 108
    static let barWidthStep: CGFloat = 4

    private enum Keys {
        static let barWidth = "barWidth"
        static let iconSize = "iconSize"
        static let showTitles = "showTitles"
        static let pinnedApps = "pinnedApps"
        static let windowAliases = "windowAliases"
        static let replaceSystemDock = "replaceSystemDock"
        static let adaptFullscreenToDock = "adaptFullscreenToDock"
        static let adaptFullscreenMigrationDone = "adaptFullscreenAutoDisabledV1"
        static let alignmentMigrationV2 = "replaceSystemDockAlignmentV2"
    }

    @Published var barWidth: CGFloat {
        didSet {
            let clamped = min(max(barWidth, Self.barWidthMin), Self.barWidthMax)
            if clamped != barWidth {
                barWidth = clamped
                return
            }
            UserDefaults.standard.set(barWidth, forKey: Keys.barWidth)
            if replaceSystemDock {
                SystemDockController.scheduleReservedWidthSync(barWidth)
            }
        }
    }

    var barWidthInt: Int {
        get { Int(barWidth.rounded()) }
        set { barWidth = CGFloat(newValue) }
    }

    @Published var iconSize: DockIconSize {
        didSet {
            if let data = try? JSONEncoder().encode(iconSize) {
                UserDefaults.standard.set(data, forKey: Keys.iconSize)
            }
        }
    }

    @Published var showTitles: Bool {
        didSet { UserDefaults.standard.set(showTitles, forKey: Keys.showTitles) }
    }

    @Published var pinnedApps: [PinnedApp] {
        didSet { persistPinnedApps() }
    }

    @Published var windowAliases: [String: String] {
        didSet { persistWindowAliases() }
    }

    /// 为 true 时隐藏屏幕底部系统程序坞，仅退出 RightDock 后恢复
    @Published var replaceSystemDock: Bool {
        didSet {
            UserDefaults.standard.set(replaceSystemDock, forKey: Keys.replaceSystemDock)
            applyReplaceSystemDockPreference()
            FullscreenLayoutEnforcer.shared.restartIfNeeded()
        }
    }

    /// 已停用自动退出原生全屏（会破坏 Electron 标题栏）；保留字段仅兼容旧配置
    @Published var adaptFullscreenToDock: Bool {
        didSet {
            if adaptFullscreenToDock {
                adaptFullscreenToDock = false
                return
            }
            UserDefaults.standard.set(false, forKey: Keys.adaptFullscreenToDock)
        }
    }

    /// 长条内图标边长（比下区固定图标略小，更紧凑）
    var barIconSize: CGFloat {
        switch iconSize {
        case .small: 18
        case .medium: 22
        case .large: 26
        }
    }

    /// 上区窗口条之间的间距
    var runningBarSpacing: CGFloat { 1 }

    /// 单条长条高度：图标 + 上下内边距（紧凑）
    var longBarHeight: CGFloat { barIconSize + 4 }

    /// 下区正方形磁贴边长（与上区图标同尺寸，略加内边距）
    var pinnedSquareSize: CGFloat { barIconSize + 4 }

    var pinnedItemSpacing: CGFloat { 2 }

    /// 下区图标网格总高度（按宽度自动换行）
    func pinnedSectionHeight(barWidth: CGFloat, appCount: Int) -> CGFloat {
        let inner = barWidth - sectionPadding * 2
        if appCount == 0 { return pinnedSquareSize }
        let cols = pinnedColumnCount(innerWidth: inner)
        let rows = (appCount + cols - 1) / cols
        return CGFloat(rows) * pinnedSquareSize + CGFloat(max(0, rows - 1)) * pinnedItemSpacing
    }

    func pinnedColumnCount(innerWidth: CGFloat) -> Int {
        let cellStride = pinnedSquareSize + pinnedItemSpacing
        return max(1, Int(floor((innerWidth + pinnedItemSpacing) / cellStride)))
    }
    var sectionPadding: CGFloat { 8 }

    /// 与 `DockRootView` 中 Divider + `.padding(.vertical, 4)` 占用高度一致，用于 AppKit 浮层对齐
    var pinnedDividerBlockHeight: CGFloat { 9 }

    private init() {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.object(forKey: Keys.barWidth) as? Double
        let initialWidth = CGFloat(storedWidth ?? Double(Self.barWidthDefault))
        barWidth = min(max(initialWidth, Self.barWidthMin), Self.barWidthMax)
        showTitles = defaults.object(forKey: Keys.showTitles) as? Bool ?? true
        let storedReplaceDock = defaults.object(forKey: Keys.replaceSystemDock) as? Bool
        if storedReplaceDock == nil {
            replaceSystemDock = true
        } else if storedReplaceDock == false,
                  defaults.object(forKey: Keys.alignmentMigrationV2) as? Bool != true {
            // 旧版默认关闭导致最大化无法贴齐 Dock 左缘，升级后自动重新开启一次
            replaceSystemDock = true
            defaults.set(true, forKey: Keys.replaceSystemDock)
            defaults.set(true, forKey: Keys.alignmentMigrationV2)
        } else if storedReplaceDock == false,
                  defaults.object(forKey: Keys.alignmentMigrationV2) as? Bool == true {
            // 修复曾写入迁移标记但未持久化开关的情况
            replaceSystemDock = true
            defaults.set(true, forKey: Keys.replaceSystemDock)
        } else {
            replaceSystemDock = storedReplaceDock ?? true
        }
        adaptFullscreenToDock = false
        if defaults.object(forKey: Keys.adaptFullscreenMigrationDone) as? Bool != true {
            defaults.set(false, forKey: Keys.adaptFullscreenToDock)
            defaults.set(true, forKey: Keys.adaptFullscreenMigrationDone)
        }

        if let data = defaults.data(forKey: Keys.iconSize),
           let size = try? JSONDecoder().decode(DockIconSize.self, from: data) {
            iconSize = size
        } else {
            iconSize = .medium
        }

        if let data = defaults.data(forKey: Keys.pinnedApps),
           let apps = try? JSONDecoder().decode([PinnedApp].self, from: data) {
            pinnedApps = apps
        } else {
            pinnedApps = Self.defaultPinnedApps
        }

        if let data = defaults.data(forKey: Keys.windowAliases),
           let aliases = try? JSONDecoder().decode([String: String].self, from: data) {
            windowAliases = aliases
        } else {
            windowAliases = [:]
        }

        ensureBuiltInFolderPins()
    }

    func displayTitle(aliasKey: String, default defaultTitle: String) -> String {
        guard let custom = windowAliases[aliasKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !custom.isEmpty else {
            return defaultTitle
        }
        return custom
    }

    func hasCustomAlias(for aliasKey: String) -> Bool {
        guard let name = windowAliases[aliasKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !name.isEmpty
    }

    func setCustomAlias(_ name: String, for aliasKey: String) {
        var next = windowAliases
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            next.removeValue(forKey: aliasKey)
        } else {
            next[aliasKey] = trimmed
        }
        windowAliases = next
    }

    func clearCustomAlias(for aliasKey: String) {
        var next = windowAliases
        next.removeValue(forKey: aliasKey)
        windowAliases = next
    }

    private func persistWindowAliases() {
        if let data = try? JSONEncoder().encode(windowAliases) {
            UserDefaults.standard.set(data, forKey: Keys.windowAliases)
        }
    }

    static let folderPinBundleIdentifier = "com.mactools.RightDock.folder-pin"
    private static var defaultPinnedApps: [PinnedApp] {
        [
            macintoshHDRootPin,
            PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder"),
            PinnedApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
            trashPin,
        ]
    }

    static var macintoshHDRootPin: PinnedApp {
        PinnedApp(
            bundleIdentifier: folderPinBundleIdentifier,
            displayName: "Macintosh HD",
            folderPath: "/"
        )
    }

    static var trashPin: PinnedApp {
        PinnedApp(bundleIdentifier: PinnedApp.trashPinBundleIdentifier, displayName: "废纸篓")
    }

    private func ensureBuiltInFolderPins() {
        if !pinnedApps.contains(where: { $0.folderPath == "/" }) {
            pinnedApps.insert(Self.macintoshHDRootPin, at: 0)
        }
        if !pinnedApps.contains(where: { $0.bundleIdentifier == PinnedApp.trashPinBundleIdentifier }) {
            pinnedApps.append(Self.trashPin)
        }
    }

    private func persistPinnedApps() {
        if let data = try? JSONEncoder().encode(pinnedApps) {
            UserDefaults.standard.set(data, forKey: Keys.pinnedApps)
        }
    }

    func addPinned(bundleIdentifier: String, displayName: String) {
        guard !pinnedApps.contains(where: { $0.bundleIdentifier == bundleIdentifier && !$0.isFolderPin }) else { return }
        pinnedApps.append(PinnedApp(bundleIdentifier: bundleIdentifier, displayName: displayName, folderPath: nil))
    }

    func addPinnedFolder(path: String, displayName: String) {
        let normalized = (path as NSString).standardizingPath
        guard !normalized.isEmpty else { return }
        guard !pinnedApps.contains(where: { $0.folderPath == normalized }) else { return }
        pinnedApps.append(PinnedApp(
            bundleIdentifier: Self.folderPinBundleIdentifier,
            displayName: displayName,
            folderPath: normalized
        ))
    }

    func removePinned(withId id: String) {
        pinnedApps.removeAll { $0.id == id }
    }

    func removePinned(at offsets: IndexSet) {
        pinnedApps.remove(atOffsets: offsets)
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        pinnedApps.move(fromOffsets: source, toOffset: destination)
    }

    private func applyReplaceSystemDockPreference() {
        if replaceSystemDock {
            SystemDockController.ensureReplacementActive(reservedWidth: barWidth)
        } else {
            SystemDockController.restoreSystemDock()
        }
    }
}
