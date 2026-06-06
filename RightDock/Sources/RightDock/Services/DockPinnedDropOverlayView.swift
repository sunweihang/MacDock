import AppKit

/// 盖在快捷区最上层；仅在系统拖放进行中参与 hitTest，避免挡住平时点击。
@MainActor
final class DockPinnedDropOverlayView: NSView {
    weak var settings: DockSettings?
    var onPinnedListChanged: (() -> Void)?
    weak var dragFeedback: PinnedDropDragFeedback?

    private var dragAcceptsApplication = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0.02
        registerForDraggedTypes(AppDropPasteboard.dragTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 拖放由全局监听处理；此处不参与点击命中，避免拖放板残留时挡住快捷区。
        nil
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragAcceptsApplication = AppDropPasteboard.quickAcceptsApplicationDrag(sender.draggingPasteboard)
        updateFeedback(sender)
        return dragAcceptsApplication ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !dragAcceptsApplication {
            dragAcceptsApplication = AppDropPasteboard.quickAcceptsApplicationDrag(sender.draggingPasteboard)
        }
        updateFeedback(sender)
        return dragAcceptsApplication ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragAcceptsApplication = false
        dragFeedback?.clear()
    }

    private func updateFeedback(_ sender: NSDraggingInfo) {
        dragFeedback?.update(
            draggingApplication: dragAcceptsApplication,
            targeted: dragAcceptsApplication,
            pasteboard: sender.draggingPasteboard
        )
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        AppDropPasteboard.quickAcceptsApplicationDrag(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragFeedback?.clear()
        guard let settings else { return false }
        let added = PinnedAppDropper.addApplications(from: sender.draggingPasteboard, settings: settings)
        if added {
            onPinnedListChanged?()
        }
        return added
    }
}
