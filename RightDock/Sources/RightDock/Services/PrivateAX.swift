import ApplicationServices
import CoreGraphics

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<UInt32>) -> AXError

enum PrivateAX {
    /// 将 AX 窗口映射为 CGWindowID（与 Rectangle 相同，比 AXWindowID 属性更准）
    static func cgWindowID(for element: AXUIElement) -> CGWindowID? {
        var identifier: UInt32 = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success else {
            return nil
        }
        return CGWindowID(identifier)
    }
}
