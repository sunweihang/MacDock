import AppKit
import SwiftUI

struct PinnedAppsSectionView: View {
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService

    private var innerWidth: CGFloat {
        settings.barWidth - settings.sectionPadding * 2
    }

    private var gridHeight: CGFloat {
        settings.pinnedSectionHeight(barWidth: settings.barWidth, appCount: settings.pinnedApps.count)
    }

    private var columns: [GridItem] {
        let count = max(1, settings.pinnedColumnCount(innerWidth: innerWidth))
        return Array(
            repeating: GridItem(.fixed(settings.pinnedSquareSize), spacing: settings.pinnedItemSpacing),
            count: count
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: settings.pinnedItemSpacing) {
            ForEach(settings.pinnedApps) { app in
                PinnedAppButton(app: app, settings: settings, runningApps: runningApps)
            }
        }
        .frame(width: innerWidth, height: gridHeight, alignment: .topLeading)
        .help("将 .app 拖到下方图标区可添加快捷方式")
    }
}

private struct PinnedAppButton: View {
    let app: PinnedApp
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService

    private var isRunning: Bool {
        guard !app.isFolderPin else { return false }
        return runningApps.runningApps.contains { $0.bundleIdentifier == app.bundleIdentifier }
    }

    private var isActive: Bool {
        guard isRunning,
              let front = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return front.bundleIdentifier == app.bundleIdentifier
    }

    var body: some View {
        Button {
            AppLauncher.activate(pinned: app, showAllWindows: false)
        } label: {
            PinnedAppIconLabel(
                icon: AppLauncher.icon(for: app),
                iconSize: settings.barIconSize,
                tileSize: settings.pinnedSquareSize,
                isRunning: isRunning,
                isActive: isActive
            )
        }
        .buttonStyle(.plain)
        .help(app.isFolderPin ? "\(app.displayName)\n\(app.folderPath ?? "")" : app.displayName)
        .contextMenu {
            Button(app.isFolderPin ? "在访达中打开" : "打开 / 切换到窗口") {
                AppLauncher.activate(pinned: app, showAllWindows: false)
            }
            if isRunning {
                Button("显示该应用全部窗口") {
                    AppLauncher.activate(pinned: app, showAllWindows: true)
                }
            }
            Divider()
            Button("从快捷方式移除", role: .destructive) {
                settings.removePinned(withId: app.id)
            }
        }
    }
}

private struct PinnedAppIconLabel: View {
    let icon: NSImage
    let iconSize: CGFloat
    let tileSize: CGFloat
    let isRunning: Bool
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(width: tileSize, height: tileSize)

            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .opacity(isRunning ? 1 : 0.88)

            if isRunning && !isActive {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .padding(2)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .contentShape(Rectangle())
    }
}

/// 仅占位对齐布局；真实图标与点击在 `DockPanelController` 的 AppKit 浮层上。
struct PinnedAppsSectionPlaceholder: View {
    @ObservedObject var settings: DockSettings

    private var innerWidth: CGFloat {
        settings.barWidth - settings.sectionPadding * 2
    }

    private var gridHeight: CGFloat {
        settings.pinnedSectionHeight(barWidth: settings.barWidth, appCount: settings.pinnedApps.count)
    }

    var body: some View {
        Color.clear
            .frame(width: innerWidth, height: gridHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
