import AppKit
import ApplicationServices
import CoreGraphics

enum WindowBoundsMatcher {
    private static let tolerance: CGFloat = 12
    private static let looseTolerance: CGFloat = 28

    private static var globalScreenMaxY: CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
    }

    /// `CGWindowList` 的 bounds（左上角原点，Y 向下）→ 与 `NSScreen.frame` 一致的全局左下角坐标
    static func screenBoundsBottomLeft(fromCGWindowBounds cg: CGRect) -> CGRect {
        let maxY = globalScreenMaxY
        return CGRect(
            x: cg.origin.x,
            y: maxY - cg.origin.y - cg.height,
            width: cg.width,
            height: cg.height
        )
    }

    /// 全局左下角矩形 → AX 左上角 position + size
    static func axFrame(fromScreenBoundsBottomLeft rect: CGRect) -> CGRect {
        let maxY = globalScreenMaxY
        return CGRect(
            x: rect.origin.x,
            y: maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// CGWindow bounds → AX 坐标（用于与 `axFrame(of:)` 比较）
    static func axStyleFrame(fromCG bounds: CGRect) -> CGRect {
        axFrame(fromScreenBoundsBottomLeft: screenBoundsBottomLeft(fromCGWindowBounds: bounds))
    }

    static func axFrame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    static func framesMatch(cgBounds: CGRect, axFrame: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        let target = axStyleFrame(fromCG: cgBounds)
        return abs(target.origin.x - axFrame.origin.x) <= tolerance
            && abs(target.origin.y - axFrame.origin.y) <= tolerance
            && abs(target.width - axFrame.width) <= tolerance
            && abs(target.height - axFrame.height) <= tolerance
    }

    static func framesMatchLoose(cgBounds: CGRect, axFrame: CGRect) -> Bool {
        framesMatch(cgBounds: cgBounds, axFrame: axFrame, tolerance: looseTolerance)
    }

    static func centerDistance(cgBounds: CGRect, axFrame: CGRect) -> CGFloat {
        let target = axStyleFrame(fromCG: cgBounds)
        return hypot(target.midX - axFrame.midX, target.midY - axFrame.midY)
    }

    static func stableSortKey(cgBounds: CGRect) -> (CGFloat, CGFloat, CGFloat) {
        stableSortKeyAX(axStyleFrame(fromCG: cgBounds))
    }

    static func stableSortKeyAX(_ axFrame: CGRect) -> (CGFloat, CGFloat, CGFloat) {
        (axFrame.minY, axFrame.minX, -(axFrame.width * axFrame.height))
    }

    static func cgWindowID(matchingAXFrame axFrame: CGRect, pid: pid_t) -> CGWindowID? {
        let candidates = WindowEnumerator.onScreenWindows().filter { $0.pid == pid }
        return candidates.first { framesMatch(cgBounds: $0.bounds, axFrame: axFrame) }?.windowID
    }

    @discardableResult
    static func setAXFrame(_ element: AXUIElement, screenRectBottomLeftOrigin rect: CGRect) -> Bool {
        let ax = axFrame(fromScreenBoundsBottomLeft: rect)
        var topLeft = ax.origin
        var size = ax.size

        guard let positionValue = AXValueCreate(.cgPoint, &topLeft),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }
        let posOK = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue) == .success
        let sizeOK = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
        return posOK && sizeOK
    }

    /// 只改宽度，不动 position/高度（Cocos 等 Electron 对同时写 position+size 较敏感）。
    @discardableResult
    static func setAXWidth(_ element: AXUIElement, width: CGFloat) -> Bool {
        guard var frame = axFrame(of: element) else { return false }
        frame.size.width = max(200, width)
        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
    }

    /// Option+绿色按钮「填满屏幕」：宽高接近该屏 `visibleFrame`（普通绿键 Zoom 不算）。
    static func matchesOptionFillScreen(cgBounds: CGRect, on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        guard visible.width > 1, visible.height > 1 else { return false }

        let screenBL = screenBoundsBottomLeft(fromCGWindowBounds: cgBounds)
        let widthRatio = screenBL.width / visible.width
        let heightRatio = screenBL.height / visible.height
        guard widthRatio >= 0.9, heightRatio >= 0.9 else { return false }

        guard screenBL.origin.x <= visible.origin.x + 28 else { return false }
        return true
    }

    /// Option+填满后：保留系统给出的位置与高度，仅把右缘收到 RightDock 左缘。
    static func frameAvoidingRightDockForFillLayout(
        on screen: NSScreen,
        dockLeftX: CGFloat,
        currentCGBounds cg: CGRect
    ) -> CGRect {
        let visible = screen.visibleFrame
        let current = screenBoundsBottomLeft(fromCGWindowBounds: cg)
        let rightEdge = min(visible.maxX, dockLeftX)
        return CGRect(
            x: current.origin.x,
            y: current.origin.y,
            width: max(200, rightEdge - current.origin.x),
            height: current.height
        )
    }

    static func screenMaxX(fromCGBounds cg: CGRect) -> CGFloat {
        screenBoundsBottomLeft(fromCGWindowBounds: cg).maxX
    }

    static func screenForWindow(cgBounds: CGRect) -> NSScreen? {
        let screenBL = screenBoundsBottomLeft(fromCGWindowBounds: cgBounds)
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screenBL.intersection(screen.frame)
            let area = max(0, intersection.width) * max(0, intersection.height)
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }
}
