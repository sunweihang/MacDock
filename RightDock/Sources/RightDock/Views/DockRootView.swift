import AppKit
import SwiftUI

extension Notification.Name {
    static let rightDockOpenSettings = Notification.Name("rightDockOpenSettings")
    static let rightDockQuit = Notification.Name("rightDockQuit")
    static let rightDockRestoreTitleBar = Notification.Name("rightDockRestoreTitleBar")
}

struct DockRootView: View {
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService
    @ObservedObject var metrics: DockPanelMetrics
    var onLayoutChange: () -> Void

    private var totalHeight: CGFloat {
        metrics.height
    }

    var body: some View {
        dockChrome
            .frame(maxWidth: .infinity, maxHeight: totalHeight)
            .contextMenu {
                Button("设置…") {
                    NotificationCenter.default.post(name: .rightDockOpenSettings, object: nil)
                }
                Button("恢复窗口标题栏") {
                    NotificationCenter.default.post(name: .rightDockRestoreTitleBar, object: nil)
                }
                Divider()
                Button("重新显示 Dock") {
                    NotificationCenter.default.post(name: Notification.Name("rightDockShow"), object: nil)
                }
                Button("隐藏 RightDock") {
                    NotificationCenter.default.post(name: Notification.Name("rightDockHide"), object: nil)
                }
                Divider()
                Button("退出 RightDock") {
                    NotificationCenter.default.post(name: .rightDockQuit, object: nil)
                }
            }
            .onChange(of: settings.barWidth) { _ in onLayoutChange() }
            .onChange(of: settings.iconSize) { _ in onLayoutChange() }
            .onChange(of: settings.pinnedApps.count) { _ in onLayoutChange() }
            .onChange(of: metrics.height) { _ in }
    }

    private var dockChrome: some View {
        VStack(spacing: 0) {
            RunningAppsSection(settings: settings, runningApps: runningApps)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(0)
                .clipped()

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.vertical, 4)

            PinnedAppsSectionPlaceholder(settings: settings)
                .layoutPriority(1)
        }
        .padding(.vertical, settings.sectionPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { dockBackground }
    }

    @ViewBuilder
    private var dockBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if metrics.isLiveResizingWidth {
            shape.fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.92))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, x: -4, y: 0)
        }
    }
}
