import Combine
import Foundation

/// AppKit 面板实际尺寸；避免 NSHostingView 按内容收缩导致 SwiftUI 拿不到全屏高度。
@MainActor
final class DockPanelMetrics: ObservableObject {
    @Published var height: CGFloat = 800
    @Published var width: CGFloat = 120
    /// 拖拽调宽中为 true：SwiftUI 用纯色底，减少毛玻璃重绘闪烁
    @Published var isLiveResizingWidth = false
}
