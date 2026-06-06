import AppKit
import SwiftUI

extension Notification.Name {
    static let rightDockRenameRequest = Notification.Name("rightDockRenameRequest")
}

struct RenameRequestPayload {
    let aliasKey: String
    let defaultTitle: String
    let currentDisplayTitle: String
    /// 关闭改名面板后恢复到此应用，避免 RightDock 占住前台导致无法切换窗口
    let restorePID: pid_t?
}

@MainActor
final class RenamePanelPresenter: NSObject {
    static let shared = RenamePanelPresenter()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var onSaveCallback: ((String) -> Void)?
    private var restorePID: pid_t?

    private override init() {
        super.init()
    }

    func present(
        anchorDockFrame: NSRect,
        payload: RenameRequestPayload,
        onSave: @escaping (String) -> Void
    ) {
        closePanel(restoreFocus: false)

        onSaveCallback = onSave
        restorePID = payload.restorePID

        let root = RenameSheetHost(
            defaultTitle: payload.defaultTitle,
            currentDisplayTitle: payload.currentDisplayTitle,
            initialText: payload.currentDisplayTitle,
            onSave: { [weak self] name in
                self?.onSaveCallback?(name)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let size = NSSize(width: 272, height: 248)
        let origin = panelOrigin(dockFrame: anchorDockFrame, panelSize: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "自定义名称"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        // 非激活面板：可输入但不把 RightDock 变成前台应用
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        closePanel(restoreFocus: true)
    }

    private func closePanel(restoreFocus: Bool) {
        panel?.resignKey()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        onSaveCallback = nil

        if restoreFocus {
            restorePreviousFocus()
        }
        restorePID = nil
    }

    private func restorePreviousFocus() {
        if let pid = restorePID,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isTerminated else {
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func panelOrigin(dockFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { dockFrame.midX < $0.frame.maxX } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var x = dockFrame.minX - panelSize.width - 20
        var y = dockFrame.midY - panelSize.height / 2

        x = max(visible.minX + 12, min(x, visible.maxX - panelSize.width - 12))
        y = max(visible.minY + 12, min(y, visible.maxY - panelSize.height - 12))

        return NSPoint(x: x, y: y)
    }
}
