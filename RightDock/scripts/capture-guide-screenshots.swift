#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/screenshots")

func ensureDir(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

func windowList() -> [[String: Any]] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return raw
}

func captureWindow(id: CGWindowID, to path: URL, pad: CGFloat = 12) -> Bool {
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        id,
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return false }

    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    let rect = CGRect(x: -pad, y: -pad, width: w + pad * 2, height: h + pad * 2)
    guard let ctx = CGContext(
        data: nil,
        width: Int(rect.width),
        height: Int(rect.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }

    ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.draw(image, in: CGRect(x: pad, y: pad, width: w, height: h))

    guard let padded = ctx.makeImage() else { return false }
    let rep = NSBitmapImageRep(cgImage: padded)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    try? png.write(to: path)
    return FileManager.default.fileExists(atPath: path.path)
}

func captureScreen(rect: CGRect, to path: URL) -> Bool {
    guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else {
        return false
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    try? png.write(to: path)
    return true
}

func runAppleScript(_ source: String) {
    var error: NSDictionary?
    let script = NSAppleScript(source: source)
    _ = script?.executeAndReturnError(&error)
}

ensureDir(outDir)

// 1. Dock 面板
var dockCaptured = false
for w in windowList() {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "RightDock",
          let layer = w[kCGWindowLayer as String] as? Int, layer == 25 || layer == 3 || layer == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
          let width = bounds["Width"], width > 60, width < 260,
          let height = bounds["Height"], height > 300,
          let wid = w[kCGWindowNumber as String] as? Int else { continue }
    let path = outDir.appendingPathComponent("01-dock-panel.png")
    if captureWindow(id: CGWindowID(wid), to: path) {
        dockCaptured = true
        print("ok dock", path.path)
        break
    }
}

// 2. 打开菜单栏菜单并截图右上角
runAppleScript("""
tell application "RightDock" to activate
delay 0.4
tell application "System Events"
  tell process "RightDock"
    set frontmost to true
    try
      click menu bar item 1 of menu bar 2
    end try
  end tell
end tell
""")
Thread.sleep(forTimeInterval: 0.7)
if let screen = NSScreen.main {
    let f = screen.frame
    let rect = CGRect(x: f.maxX - 420, y: f.maxY - 520, width: 420, height: 520)
    let path = outDir.appendingPathComponent("02-menu-bar.png")
    if captureScreen(rect: rect, to: path) { print("ok menu", path.path) }
}

// 3. 打开设置窗口
runAppleScript("""
tell application "System Events"
  tell process "RightDock"
    try
      click menu item "设置…" of menu 1 of menu bar item 1 of menu bar 2
    end try
  end tell
end tell
""")
Thread.sleep(forTimeInterval: 1.0)
for w in windowList() {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "RightDock",
          let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
          let width = bounds["Width"], width > 350, width < 520,
          let wid = w[kCGWindowNumber as String] as? Int else { continue }
    let path = outDir.appendingPathComponent("03-settings.png")
    if captureWindow(id: CGWindowID(wid), to: path, pad: 16) {
        print("ok settings", path.path)
        break
    }
}

// 4. 辅助功能设置
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
Thread.sleep(forTimeInterval: 2.5)
for w in windowList() {
    guard let owner = w[kCGWindowOwnerName as String] as? String,
          owner == "系统设置" || owner == "System Settings",
          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
          let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
          let width = bounds["Width"], width > 700,
          let wid = w[kCGWindowNumber as String] as? Int else { continue }
    let path = outDir.appendingPathComponent("04-accessibility.png")
    if captureWindow(id: CGWindowID(wid), to: path, pad: 8) {
        print("ok accessibility", path.path)
        break
    }
}

// 5. 全屏概览（展示 Dock + 桌面）
if let screen = NSScreen.main {
    let path = outDir.appendingPathComponent("05-desktop-overview.png")
    if captureScreen(rect: screen.frame, to: path) { print("ok overview", path.path) }
}

print("done")
