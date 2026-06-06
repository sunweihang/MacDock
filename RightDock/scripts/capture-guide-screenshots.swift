#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/screenshots")

// MARK: - Helpers

func ensureDir(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

@discardableResult
func shell(_ args: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = args
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    } catch {
        return 1
    }
}

func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    if error != nil { return nil }
    return result.stringValue
}

/// AppKit 全局坐标（左下角原点）→ screencapture -R（左上角原点）
func screencaptureRect(from cocoa: CGRect) -> CGRect {
    let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? cocoa.maxY
    return CGRect(
        x: cocoa.origin.x,
        y: maxY - cocoa.maxY,
        width: cocoa.width,
        height: cocoa.height
    )
}

func captureRegion(_ cocoaRect: CGRect, to path: URL, pad: CGFloat = 0) -> Bool {
    let rect = cocoaRect.insetBy(dx: -pad, dy: -pad)
    let sc = screencaptureRect(from: rect)
    let x = Int(sc.origin.x.rounded())
    let y = Int(sc.origin.y.rounded())
    let w = Int(sc.width.rounded())
    let h = Int(sc.height.rounded())
    guard w > 0, h > 0 else { return false }
    let code = shell(["screencapture", "-x", "-R\(x),\(y),\(w),\(h)", path.path])
    return code == 0 && FileManager.default.fileExists(atPath: path.path)
}

func captureWindow(id: CGWindowID, to path: URL) -> Bool {
    let code = shell(["screencapture", "-x", "-l\(id)", path.path])
    return code == 0 && FileManager.default.fileExists(atPath: path.path)
}

func windowList() -> [[String: Any]] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return raw
}

func cocoaBounds(_ dict: [String: Any]) -> CGRect? {
    guard let b = dict[kCGWindowBounds as String] as? [String: CGFloat],
          let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { return nil }
    return CGRect(x: x, y: y, width: w, height: h)
}

func rightDockPanel() -> (id: CGWindowID, bounds: CGRect)? {
    for w in windowList() {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "RightDock",
              let bounds = cocoaBounds(w),
              bounds.width > 60, bounds.width < 280, bounds.height > 200,
              let wid = w[kCGWindowNumber as String] as? Int else { continue }
        return (CGWindowID(wid), bounds)
    }
    return nil
}

func screenContaining(_ point: CGPoint) -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(point) }
}

func displayIndex(for screen: NSScreen) -> Int? {
    guard let idx = NSScreen.screens.firstIndex(of: screen) else { return nil }
    return idx + 1
}

func loadCGImage(_ path: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(path as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

@discardableResult
func savePNG(_ image: NSImage, to path: URL) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return false }
    try? data.write(to: path)
    return true
}

/// 系统设置窗口 sharingState=0，无「屏幕录制」权限时 screencapture 只能截到壁纸；生成示意截图供 README 使用。
func renderAccessibilityGuide(to path: URL) -> Bool {
    let w: CGFloat = 920
    let h: CGFloat = 620
    let image = NSImage(size: NSSize(width: w, height: h))
    image.lockFocus()

    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()

    NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 230, height: h).fill()

    let heading: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]
    let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.labelColor,
    ]
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: NSColor.labelColor,
    ]

    "隐私与安全性".draw(at: NSPoint(x: 16, y: h - 36), withAttributes: heading)
    "辅助功能".draw(at: NSPoint(x: 16, y: h - 80), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.labelColor])
    "自动化".draw(at: NSPoint(x: 16, y: h - 110), withAttributes: body)

    "辅助功能".draw(at: NSPoint(x: 260, y: h - 52), withAttributes: title)
    ("允许此电脑上的 App 控制你的电脑。\n" as NSString).draw(
        in: NSRect(x: 260, y: h - 110, width: 620, height: 40),
        withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
    )

    let rowY: CGFloat = h - 200
    NSColor.white.setFill()
    NSRect(x: 250, y: rowY - 10, width: w - 270, height: 52).fill()
    NSColor.separatorColor.setStroke()
    NSBezierPath(rect: NSRect(x: 250, y: rowY - 10, width: w - 270, height: 52)).stroke()

    let icon = NSWorkspace.shared.icon(forFile: "/Applications/RightDock.app")
    icon.size = NSSize(width: 28, height: 28)
    icon.draw(in: NSRect(x: 264, y: rowY, width: 28, height: 28))
    "RightDock.app".draw(at: NSPoint(x: 302, y: rowY + 4), withAttributes: body)

    NSColor.systemGreen.setFill()
    NSBezierPath(roundedRect: NSRect(x: w - 120, y: rowY + 6, width: 44, height: 24), xRadius: 12, yRadius: 12).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: w - 92, y: rowY + 10, width: 16, height: 16)).fill()

    ("提示：在列表中找到 /Applications/RightDock.app 并打开开关。" as NSString).draw(
        at: NSPoint(x: 260, y: 80),
        withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    )

    image.unlockFocus()
    return savePNG(image, to: path)
}

/// 将应用内导出的 Dock 条贴回显示器截图右侧（系统 screencapture 无法捕获 NSPanel）
func compositeDockOntoDisplay(displayPath: URL, dockPath: URL, dockWidth: CGFloat, to outPath: URL) -> Bool {
    guard let display = loadCGImage(displayPath), let dock = loadCGImage(dockPath) else { return false }
    let w = display.width
    let h = display.height
    let dockW = min(Int(dockWidth.rounded()), dock.width, w / 4)
    let dockH = min(h, dock.height)

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }

    ctx.draw(display, in: CGRect(x: 0, y: 0, width: w, height: h))
    let dest = CGRect(x: w - dockW, y: 0, width: dockW, height: dockH)
    ctx.draw(dock, in: dest)

    guard let result = ctx.makeImage() else { return false }
    let rep = NSBitmapImageRep(cgImage: result)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    try? png.write(to: outPath)
    return true
}

// MARK: - Capture

ensureDir(outDir)

print("从应用内导出 Dock / 菜单 / 设置…")
_ = shell(["pkill", "-x", "RightDock"])
Thread.sleep(forTimeInterval: 0.6)

let appBin = "/Applications/RightDock.app/Contents/MacOS/RightDock"
let exportCode = shell([appBin, "--capture-readme-screenshots=\(outDir.path)"])
if exportCode != 0 {
    print("warn: app export exited \(exportCode)")
}
Thread.sleep(forTimeInterval: 0.5)

for name in ["01-dock-panel.png", "02-menu-bar.png", "03-settings.png"] {
    let p = outDir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: p.path) { print("ok export", name) }
    else { print("fail export", name) }
}

// 4. 辅助功能设置（系统设置窗口 sharingNone，无屏幕录制权限时 screencapture 只会得到壁纸）
let axPath = outDir.appendingPathComponent("04-accessibility.png")
if renderAccessibilityGuide(to: axPath) {
    print("ok accessibility", axPath.path)
} else {
    print("fail accessibility")
}

// 5–6. 桌面概览与窗口对齐（Dock 所在显示器）
_ = shell(["open", "-a", "/Applications/RightDock.app"])
Thread.sleep(forTimeInterval: 1.2)
_ = shell(["open", "-a", "Cursor"])
Thread.sleep(forTimeInterval: 1.0)

let dockPath = outDir.appendingPathComponent("01-dock-panel.png")
let dockWidth: CGFloat = {
    if let dock = rightDockPanel() { return dock.bounds.width }
    if let img = NSImage(contentsOf: dockPath) { return img.size.width }
    return 160
}()

if let dock = rightDockPanel(),
   let screen = screenContaining(CGPoint(x: dock.bounds.midX, y: dock.bounds.midY)),
   let displayIdx = displayIndex(for: screen) {

    let rawOverview = outDir.appendingPathComponent("_05-raw.png")
    let overviewPath = outDir.appendingPathComponent("05-desktop-overview.png")
    if shell(["screencapture", "-x", "-D\(displayIdx)", rawOverview.path]) == 0 {
        if compositeDockOntoDisplay(displayPath: rawOverview, dockPath: dockPath, dockWidth: dockWidth, to: overviewPath) {
            print("ok overview display \(displayIdx)", overviewPath.path)
        } else {
            try? FileManager.default.copyItem(at: rawOverview, to: overviewPath)
            print("ok overview (no composite)", overviewPath.path)
        }
        try? FileManager.default.removeItem(at: rawOverview)
    } else {
        print("fail overview")
    }

    let sf = screen.frame
    let alignedRect = CGRect(
        x: sf.minX,
        y: sf.minY + 38,
        width: sf.width - dockWidth - 8,
        height: sf.height - 38
    )
    let rawAligned = outDir.appendingPathComponent("_06-raw.png")
    let alignedPath = outDir.appendingPathComponent("06-window-aligned.png")
    if captureRegion(alignedRect, to: rawAligned) {
        let compositeW = Int(alignedRect.width + dockWidth + 8)
        if let left = loadCGImage(rawAligned), let dockImg = loadCGImage(dockPath),
           let ctx = CGContext(
               data: nil,
               width: compositeW,
               height: left.height,
               bitsPerComponent: 8, bytesPerRow: 0,
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            ctx.draw(left, in: CGRect(x: 0, y: 0, width: left.width, height: left.height))
            let dockW = min(Int(dockWidth), dockImg.width)
            ctx.draw(dockImg, in: CGRect(x: left.width, y: 0, width: dockW, height: min(left.height, dockImg.height)))
            if let result = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: result)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: alignedPath)
                    print("ok aligned", alignedPath.path)
                }
            }
        } else {
            try? FileManager.default.copyItem(at: rawAligned, to: alignedPath)
            print("ok aligned (no composite)", alignedPath.path)
        }
        try? FileManager.default.removeItem(at: rawAligned)
    } else {
        print("fail aligned")
    }
} else {
    print("fail overview/aligned: dock screen not found")
}

print("done")
