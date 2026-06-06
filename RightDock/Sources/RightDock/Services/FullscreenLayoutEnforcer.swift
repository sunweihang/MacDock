import AppKit
import ApplicationServices

/// 仅处理 Option+绿色按钮「填满屏幕」；普通绿键 Zoom 不干预。
@MainActor
final class FullscreenLayoutEnforcer {
    static let shared = FullscreenLayoutEnforcer()

    private weak var settings: DockSettings?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastAdjustKey: String?
    private var lastAdjustTime = Date.distantPast
    private var pendingFullscreenExitKey: String?
    private let cooldown: TimeInterval = 0.8

    private init() {}

    func start(settings: DockSettings) {
        self.settings = settings
        stop()
        guard settings.replaceSystemDock else { return }
        installObservers()
        enforceIfNeeded()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        lastAdjustKey = nil
        pendingFullscreenExitKey = nil
    }

    func restartIfNeeded() {
        guard let settings else { return }
        if settings.replaceSystemDock {
            start(settings: settings)
        } else {
            stop()
        }
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    FullscreenLayoutEnforcer.shared.scheduleEnforce()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    FullscreenLayoutEnforcer.shared.enforceIfNeeded()
                }
            }
        )

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                FullscreenLayoutEnforcer.shared.enforceIfNeeded()
            }
        }
    }

    private func scheduleEnforce() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.enforceIfNeeded()
        }
    }

    func enforceIfNeeded() {
        guard let settings,
              settings.replaceSystemDock,
              AccessibilityTrust.queryWithoutPrompt() else {
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier,
              !AppBundlePolicy.shouldSkipLayoutEnforcement(bundleIdentifier: bundleId) else {
            return
        }

        let pid = app.processIdentifier
        let isElectron = AppBundlePolicy.isElectron(bundleIdentifier: bundleId)

        guard let window = WindowFocusHelper.focusedWindowElement(pid: pid) else {
            return
        }

        guard let cgID = PrivateAX.cgWindowID(for: window),
              let cgWindow = WindowEnumerator.onScreenWindows().first(where: { $0.windowID == cgID }) else {
            return
        }

        guard let hostScreen = DockScreenLayout.hostScreen(),
              let windowScreen = WindowBoundsMatcher.screenForWindow(cgBounds: cgWindow.bounds),
              DockScreenLayout.screensAreEqual(windowScreen, hostScreen) else {
            return
        }

        guard WindowBoundsMatcher.matchesOptionFillScreen(cgBounds: cgWindow.bounds, on: windowScreen) else {
            return
        }

        let dockLeft = DockScreenLayout.dockLeftEdge(for: hostScreen, barWidth: settings.barWidth)
        guard WindowBoundsMatcher.screenMaxX(fromCGBounds: cgWindow.bounds) > dockLeft + 4 else { return }

        let target = WindowBoundsMatcher.frameAvoidingRightDockForFillLayout(
            on: windowScreen,
            dockLeftX: dockLeft,
            currentCGBounds: cgWindow.bounds
        )
        let currentAX = WindowBoundsMatcher.axFrame(of: window)
        let targetAX = WindowBoundsMatcher.axFrame(fromScreenBoundsBottomLeft: target)

        guard shouldAdjust(currentAX: currentAX, targetAX: targetAX, dockLeftX: dockLeft) else {
            return
        }

        if axBool(window, "AXFullScreen") == true {
            guard isElectron,
                  AccessibilityTrust.automationIsGranted(),
                  let processName = ElectronWindowLayout.processName(for: app) else {
                return
            }
            let key = "fs-\(pid)-\(cgID)"
            if pendingFullscreenExitKey == key { return }
            pendingFullscreenExitKey = key
            if ElectronWindowLayout.exitNativeFullscreen(processName: processName) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.pendingFullscreenExitKey = nil
                    self?.enforceIfNeeded()
                }
            } else {
                pendingFullscreenExitKey = nil
            }
            return
        }

        let key = "\(pid)-\(cgID)"
        if key == lastAdjustKey, Date().timeIntervalSince(lastAdjustTime) < cooldown {
            return
        }

        // Cursor 等 Electron：AppleScript position 在多屏上会偏移，统一走 AX 只改宽度。
        let applied = WindowBoundsMatcher.setAXFrame(window, screenRectBottomLeftOrigin: target)

        if applied {
            lastAdjustKey = key
            lastAdjustTime = Date()
        }
    }

    private func shouldAdjust(
        currentAX: CGRect?,
        targetAX: CGRect,
        dockLeftX: CGFloat
    ) -> Bool {
        guard let currentAX else { return true }
        return currentAX.maxX > dockLeftX + 4
            && (abs(currentAX.width - targetAX.width) > 6
                || abs(currentAX.maxX - targetAX.maxX) > 6)
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }
}
