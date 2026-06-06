import AppKit
import CoreGraphics

/// 从应用内直接导出 README 截图（NSPanel 默认 sharingNone，系统 screencapture 会穿透成壁纸）
@MainActor
enum ReadmeScreenshotExporter {
    static func runIfRequested(appDelegate: AppDelegate) {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--capture-readme-screenshots=") }),
              let dir = arg.split(separator: "=", maxSplits: 1).last else { return }
        let outDir = URL(fileURLWithPath: String(dir))
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            exportAll(appDelegate: appDelegate, to: outDir)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
        }
    }

    private static func exportAll(appDelegate: AppDelegate, to outDir: URL) {
        if appDelegate.exportDockScreenshot(to: outDir.appendingPathComponent("01-dock-panel.png")) {
            fputs("ok dock export\n", stderr)
        }
        if exportMenuScreenshot(appDelegate: appDelegate, to: outDir.appendingPathComponent("02-menu-bar.png")) {
            fputs("ok menu export\n", stderr)
        }
        SettingsWindowPresenter.show(settings: appDelegate.settings, runningApps: appDelegate.runningApps)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        if SettingsWindowPresenter.exportScreenshot(to: outDir.appendingPathComponent("03-settings.png")) {
            fputs("ok settings export\n", stderr)
        }
    }

    private static func exportMenuScreenshot(appDelegate: AppDelegate, to url: URL) -> Bool {
        guard let button = appDelegate.statusBarButtonForExport else { return false }
        let menu = appDelegate.statusMenuForExport()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)

        // 菜单弹出为独立窗口，稍等渲染
        usleep(400_000)

        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for w in raw {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "RightDock",
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 180, width < 400, height > 120, height < 500,
                  let wid = w[kCGWindowNumber as String] as? Int else { continue }

            guard let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(wid), [.boundsIgnoreFraming, .bestResolution]
            ) else { continue }

            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: url)
            return FileManager.default.fileExists(atPath: url.path)
        }

        return renderMenuFallback(menu: menu, to: url)
    }

    private static func renderMenuFallback(menu: NSMenu, to url: URL) -> Bool {
        let width: CGFloat = 280
        var height: CGFloat = 8
        for item in menu.items {
            height += item.isSeparatorItem ? 10 : 28
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 0.96).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var y = height - 8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]
        for item in menu.items {
            if item.isSeparatorItem {
                y -= 10
                NSColor.white.withAlphaComponent(0.15).setFill()
                NSRect(x: 12, y: y, width: width - 24, height: 1).fill()
                continue
            }
            y -= 28
            let title = item.title as NSString
            title.draw(at: NSPoint(x: 16, y: y + 6), withAttributes: attrs)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        try? data.write(to: url)
        return true
    }
}
