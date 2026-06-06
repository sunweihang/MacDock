import AppKit
import SwiftUI

struct RunningAppsSection: View {
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService

    private var contentWidth: CGFloat {
        settings.barWidth - settings.sectionPadding * 2
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: settings.runningBarSpacing) {
                if runningApps.runningApps.isEmpty {
                    Text("无运行中窗口")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: contentWidth, height: settings.longBarHeight)
                } else {
                    ForEach(runningApps.runningApps) { item in
                        RunningWindowBarView(
                            item: item,
                            settings: settings,
                            runningApps: runningApps,
                            isActive: runningApps.isActiveItem(item)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, settings.sectionPadding)
    }

}

struct RunningWindowBarView: View {
    let item: RunningWindowItem
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService
    let isActive: Bool

    private var contentWidth: CGFloat {
        settings.barWidth - settings.sectionPadding * 2
    }

    private var shownTitle: String {
        settings.displayTitle(aliasKey: item.aliasKey, default: item.defaultTitle)
    }

    private var hasCustomName: Bool {
        settings.hasCustomAlias(for: item.aliasKey)
    }

    var body: some View {
        Button(action: focusItem) {
            DockLongBarLabel(
                icon: item.icon,
                title: shownTitle,
                showTitle: settings.showTitles,
                iconSize: settings.barIconSize,
                barWidth: contentWidth,
                isActive: isActive
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .contextMenu {
            Button("自定义名称…") {
                requestRename()
            }
            Button("恢复默认名称") {
                settings.clearCustomAlias(for: item.aliasKey)
            }
            .disabled(!hasCustomName)
            Divider()
            Button("切换到该窗口") {
                focusItem()
            }
        }
    }

    private func requestRename() {
        NotificationCenter.default.post(
            name: .rightDockRenameRequest,
            object: nil,
            userInfo: [
                "aliasKey": item.aliasKey,
                "defaultTitle": item.defaultTitle,
                "currentDisplayTitle": shownTitle,
                "restorePID": NSNumber(value: item.pid),
            ]
        )
    }

    private func focusItem() {
        runningApps.highlightAfterFocus(item: item)
        WindowFocusHelper.focus(
            windowID: item.windowID,
            pid: item.pid,
            bounds: item.bounds,
            windowTitle: item.windowTitle,
            displayTitle: shownTitle
        )
    }

    private var helpText: String {
        if hasCustomName {
            return "\(shownTitle)\n（默认：\(item.defaultTitle)）"
        }
        return shownTitle
    }
}
