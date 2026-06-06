import AppKit

/// 用 AppKit 处理左缘拖拽调宽，避免 SwiftUI DragGesture 触发布局/材质闪烁。
@MainActor
final class DockPanelWidthResizeTracker: NSObject {
    private weak var panel: NSPanel?
    private let settings: DockSettings
    private weak var panelController: DockPanelController?

    private var edgeView: WidthResizeEdgeView?
    private var dragStartScreenX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    init(settings: DockSettings, panelController: DockPanelController) {
        self.settings = settings
        self.panelController = panelController
    }

    static let edgeHitWidth: CGFloat = 10

    func install(on panel: NSPanel, in container: NSView) {
        self.panel = panel
        let edge = WidthResizeEdgeView()
        edge.translatesAutoresizingMaskIntoConstraints = false
        edge.wantsLayer = true
        edge.layer?.zPosition = 30
        container.addSubview(edge)
        NSLayoutConstraint.activate([
            edge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            edge.topAnchor.constraint(equalTo: container.topAnchor),
            edge.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: Self.edgeHitWidth),
        ])
        edge.onMouseDown = { [weak self] in self?.beginDrag() }
        edge.onMouseDrag = { [weak self] in self?.continueDrag() }
        edge.onMouseUp = { [weak self] in self?.endDrag() }
        self.edgeView = edge
    }

    private func beginDrag() {
        dragStartScreenX = NSEvent.mouseLocation.x
        dragStartWidth = settings.barWidth
        panelController?.beginLiveWidthResize()
    }

    private func continueDrag() {
        let delta = NSEvent.mouseLocation.x - dragStartScreenX
        let proposed = dragStartWidth - delta
        let clamped = min(max(proposed, DockSettings.barWidthMin), DockSettings.barWidthMax)
        panelController?.applyPanelWidth(clamped)
    }

    private func endDrag() {
        guard let controller = panelController else { return }
        let width = controller.livePreviewWidth ?? settings.barWidth
        let step = DockSettings.barWidthStep
        let snapped = (width / step).rounded() * step
        controller.commitLiveWidthResize(snappedWidth: snapped)
        edgeView?.resetCursor()
    }
}

private final class WidthResizeEdgeView: NSView {
    var onMouseDown: (() -> Void)?
    var onMouseDrag: (() -> Void)?
    var onMouseUp: (() -> Void)?

    private var isDragging = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    func resetCursor() {
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        onMouseDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onMouseUp?()
        resetCursor()
    }
}
