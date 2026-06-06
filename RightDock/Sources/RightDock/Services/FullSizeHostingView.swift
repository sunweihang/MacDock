import AppKit
import SwiftUI

/// 让 SwiftUI 根视图始终铺满 AppKit 容器，而不是按内容收缩。
final class FullSizeHostingView<Content: View>: NSHostingView<Content> {
    /// 下区快捷图标由 AppKit 浮层处理点击，避免挡住底部。
    var pinnedStripExclusionHeight: CGFloat = 0
    /// 拖拽调宽期间不 invalidate，避免左缘随布局刷新闪烁
    var suppressesLayoutInvalidation = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if point.x < DockPanelWidthResizeTracker.edgeHitWidth {
            return nil
        }
        if pinnedStripExclusionHeight > 0, point.y < pinnedStripExclusionHeight {
            return nil
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        guard let container = superview?.bounds.size, container.width > 1, container.height > 1 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return container
    }

    override var fittingSize: NSSize {
        intrinsicContentSize
    }

    override func layout() {
        super.layout()
        if !suppressesLayoutInvalidation {
            invalidateIntrinsicContentSize()
        }
    }
}
