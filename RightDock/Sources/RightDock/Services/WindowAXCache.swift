import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowAXCache {
    static let shared = WindowAXCache()

    struct Snapshot {
        let element: AXUIElement
        let cgWindowID: CGWindowID?
        let axWindowID: CGWindowID?
        let frame: CGRect?
        let title: String
        let isMinimized: Bool
    }

    private init() {}

    /// 精确匹配要切换的 AX 窗口（多窗口同尺寸时靠标题/ID，不靠排序猜）
    func elementToFocus(
        pid: pid_t,
        windowID: CGWindowID,
        windowTitle: String,
        displayTitle: String
    ) -> AXUIElement? {
        let snapshots = buildSnapshots(pid: pid)
        guard !snapshots.isEmpty else { return nil }

        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty {
            if let match = snapshots.first(where: { $0.title == trimmedTitle }) {
                return match.element
            }
        }

        if !trimmedDisplay.isEmpty {
            if let match = snapshots.first(where: { $0.title == trimmedDisplay }) {
                return match.element
            }
            if let match = snapshots.first(where: {
                $0.title.localizedCaseInsensitiveContains(trimmedDisplay)
                    || trimmedDisplay.localizedCaseInsensitiveContains($0.title)
            }) {
                return match.element
            }
        }

        if windowID != 0 {
            if let match = snapshots.first(where: { $0.cgWindowID == windowID || $0.axWindowID == windowID }) {
                return match.element
            }
        }

        return rankedCandidates(
            pid: pid,
            windowID: windowID,
            bounds: .zero,
            windowTitle: windowTitle,
            displayTitle: displayTitle
        ).first
    }

    /// 按匹配得分排序的候选 AX 窗口（得分最高最可能正确）
    func rankedCandidates(
        pid: pid_t,
        windowID: CGWindowID,
        bounds: CGRect,
        windowTitle: String,
        displayTitle: String
    ) -> [AXUIElement] {
        let snapshots = buildSnapshots(pid: pid)
        guard !snapshots.isEmpty else { return [] }

        let liveBounds = WindowEnumerator.onScreenWindows()
            .first { $0.windowID == windowID }?
            .bounds ?? bounds

        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let scored = snapshots.map { snap -> (AXUIElement, Int) in
            var score = 0

            if snap.cgWindowID == windowID { score += 10_000 }
            if snap.axWindowID == windowID { score += 5_000 }

            if !trimmedDisplay.isEmpty {
                if snap.title == trimmedDisplay { score += 12_000 }
                else if snap.title.localizedCaseInsensitiveContains(trimmedDisplay) { score += 6_000 }
                else if trimmedDisplay.localizedCaseInsensitiveContains(snap.title) { score += 3_000 }
            }

            if !trimmedTitle.isEmpty {
                if snap.title == trimmedTitle { score += 8_000 }
                else if snap.title.localizedCaseInsensitiveContains(trimmedTitle) { score += 4_000 }
            }

            if let frame = snap.frame {
                if WindowBoundsMatcher.framesMatch(cgBounds: liveBounds, axFrame: frame) {
                    score += 1_000
                } else if WindowBoundsMatcher.framesMatchLoose(cgBounds: liveBounds, axFrame: frame) {
                    score += 400
                }
                let distance = WindowBoundsMatcher.centerDistance(cgBounds: liveBounds, axFrame: frame)
                score -= Int(min(distance, 300))
            } else if snap.isMinimized {
                score += 200
            }

            return (snap.element, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func buildSnapshots(pid: pid_t) -> [Snapshot] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window in
            guard isStandardWindow(window) else { return nil }

            let frame = WindowBoundsMatcher.axFrame(of: window)
            let minimized = isMinimized(window)

            if let frame, frame.width >= 80, frame.height >= 80 {
                // 正常窗口
            } else if minimized {
                // 最小化窗口允许较小/为 0 的 bounds
            } else if frame != nil {
                return nil
            }

            return Snapshot(
                element: window,
                cgWindowID: PrivateAX.cgWindowID(for: window),
                axWindowID: axWindowIDAttribute(from: window),
                frame: frame,
                title: axTitle(from: window),
                isMinimized: minimized
            )
        }
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
              let minimized = minimizedRef as? Bool else {
            return false
        }
        return minimized
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String,
              role == kAXWindowRole as String else {
            return false
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            let excluded: Set<String> = [kAXFloatingWindowSubrole as String]
            return !excluded.contains(subrole)
        }
        return true
    }

    private func axWindowIDAttribute(from element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowID" as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }

    private func axTitle(from element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return ""
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
