#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let shotDir = root.appendingPathComponent("docs/screenshots")
let pdfPath = root.appendingPathComponent("docs/RightDock-使用指南.pdf")

func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    if error != nil { return nil }
    return result.stringValue
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

func ensureDir(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

func captureRegion(_ rect: CGRect, to path: URL) {
    let x = Int(rect.origin.x.rounded())
    let y = Int(rect.origin.y.rounded())
    let w = Int(rect.width.rounded())
    let h = Int(rect.height.rounded())
    _ = shell(["screencapture", "-x", "-R\(x),\(y),\(w),\(h)", path.path])
}

func loadImage(_ path: URL) -> NSImage? {
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    return NSImage(contentsOf: path)
}

// MARK: - Screenshots（复用 capture-guide-screenshots.swift，支持多显示器与窗口捕获）
ensureDir(shotDir)
let captureScript = root.appendingPathComponent("scripts/capture-guide-screenshots.swift")
_ = shell(["swift", captureScript.path, shotDir.path])

// MARK: - PDF

let pageW: CGFloat = 595.28  // A4
let pageH: CGFloat = 841.89
let margin: CGFloat = 48
let contentW = pageW - margin * 2

var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
guard let pdf = CGContext(pdfPath as CFURL, mediaBox: &mediaBox, nil) else {
    fputs("无法创建 PDF\n", stderr)
    exit(1)
}

let fontName = "PingFangSC-Regular"
let boldName = "PingFangSC-Semibold"
let titleSize: CGFloat = 22
let hSize: CGFloat = 15
let bodySize: CGFloat = 11
let captionSize: CGFloat = 9

func font(_ name: String, size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

final class PageBuilder {
    let context: CGContext
    var y: CGFloat = pageH - margin

    init(context: CGContext) {
        self.context = context
    }

    func newPage() {
        context.endPDFPage()
        context.beginPDFPage(nil)
        y = pageH - margin
    }

    func ensure(_ height: CGFloat) {
        if y - height < margin {
            newPage()
        }
    }

    func withGraphicsContext(_ work: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let ns = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = ns
        work()
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawText(_ text: String, font: NSFont, color: NSColor = .labelColor, spacing: CGFloat = 8) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4
        para.paragraphSpacing = spacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let rect = str.boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        ensure(rect.height + 10)
        let drawRect = CGRect(x: margin, y: y - rect.height, width: contentW, height: rect.height)
        withGraphicsContext {
            str.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        y -= rect.height + spacing
    }

    func drawImage(_ path: URL, caption: String, maxHeight: CGFloat = 260) {
        guard let image = loadImage(path) else {
            drawText("（截图缺失：\(path.lastPathComponent)）", font: font(fontName, size: captionSize), color: .secondaryLabelColor)
            return
        }
        let aspect = image.size.width / max(image.size.height, 1)
        var drawH = min(maxHeight, image.size.height)
        var drawW = drawH * aspect
        if drawW > contentW {
            drawW = contentW
            drawH = drawW / aspect
        }
        ensure(drawH + 28)
        let rect = CGRect(x: margin, y: y - drawH, width: drawW, height: drawH)
        withGraphicsContext {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        y -= drawH + 6
        drawText(caption, font: font(fontName, size: captionSize), color: .secondaryLabelColor, spacing: 14)
    }
}

pdf.beginPDFPage(nil)
let page = PageBuilder(context: pdf)

page.drawText("RightDock 使用指南", font: font(boldName, size: 26), spacing: 10)
page.drawText("版本 1.0  ·  macOS 13 及以上  ·  Apple 芯片 / Intel", font: font(fontName, size: bodySize), color: .secondaryLabelColor, spacing: 20)
page.drawText(
    """
    RightDock 是贴在屏幕右侧的自定义程序坞：上区显示当前运行窗口，下区可固定常用应用。本指南介绍安装、授权、日常使用，以及分发给他人时的注意事项。
    """,
    font: font(fontName, size: bodySize)
)

page.drawText("一、安装", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    1. 将 RightDock.app 拖入「应用程序」文件夹。
    2. 首次打开若被拦截：在应用图标上右键 → 打开，或在「系统设置 → 隐私与安全性」中允许。
    3. 启动后仅在菜单栏显示「Dock」图标，不会在系统 Dock 中出现。
    """,
    font: font(fontName, size: bodySize)
)

page.drawText("二、界面概览", font: font(boldName, size: hSize), spacing: 6)
page.drawImage(shotDir.appendingPathComponent("05-desktop-overview.png"), caption: "图 1：RightDock 与 Cursor 窗口并排使用", maxHeight: 220)
page.drawImage(shotDir.appendingPathComponent("01-dock-panel.png"), caption: "图 2：右侧 Dock 面板（上区窗口列表 + 下区固定图标）", maxHeight: 300)

page.newPage()

page.drawText("三、菜单栏操作", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    · 左键点击菜单栏「Dock」：显示并置顶 RightDock
    · 右键点击：打开功能菜单（设置、隐藏、恢复系统程序坞、退出等）
    · 拖拽 Dock 左边缘约 8pt 区域：调节宽度（72–220 pt）
    """,
    font: font(fontName, size: bodySize)
)
page.drawImage(shotDir.appendingPathComponent("02-menu-bar.png"), caption: "图 3：菜单栏右键菜单", maxHeight: 240)

page.drawText("四、设置", font: font(boldName, size: hSize), spacing: 6)
page.drawImage(shotDir.appendingPathComponent("03-settings.png"), caption: "图 4：设置窗口", maxHeight: 280)
page.drawText(
    """
    重要选项：
    · 替换系统程序坞：必须开启，最大化窗口才能与 Dock 左缘对齐
    · Dock 宽度：与右侧占位宽度一致，修改后请对窗口再点一次绿色缩放按钮
    · 固定快捷方式：输入 Bundle ID 添加，或从访达拖入 .app 到底部图标区
    """,
    font: font(fontName, size: bodySize)
)

page.newPage()

page.drawText("五、权限授权（必做）", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    RightDock 需要以下权限才能切换窗口、对齐 Cursor 等应用：

    1. 辅助功能：系统设置 → 隐私与安全性 → 辅助功能 → 添加 RightDock.app 并开启
    2. 自动化：同一页面下方的「自动化」→ 允许 RightDock 控制「系统事件」

    授权后请完全退出 RightDock 再重新打开。菜单中应显示「辅助功能已生效 ✓」。
    """,
    font: font(fontName, size: bodySize)
)
page.drawImage(shotDir.appendingPathComponent("04-accessibility.png"), caption: "图 5：辅助功能设置（示例）", maxHeight: 260)

page.drawText("六、窗口与 Dock 对齐", font: font(boldName, size: hSize), spacing: 6)
page.drawImage(shotDir.appendingPathComponent("06-window-aligned.png"), caption: "图 6：最大化后窗口右缘贴齐 Dock 左缘", maxHeight: 220)
page.drawText(
    """
    · 推荐使用窗口绿色缩放按钮（非 ⌃⌘F 原生全屏）
    · Cursor 等 Electron 应用会自动缩到 Dock 左侧，约 1 秒内生效
    · 若未对齐：确认「替换系统程序坞」已开，再点一次绿色缩放
    · 若缺少红黄绿按钮：菜单选择「恢复前台窗口标题栏」
    """,
    font: font(fontName, size: bodySize)
)

page.newPage()

page.drawText("七、分发给他人", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    打包方式：在 RightDock 目录执行 ./scripts/build-app.sh，将生成的 RightDock.app 压缩为 zip 发送。

    对方安装步骤：
    1. 解压并拖入「应用程序」
    2. 右键 → 打开（首次）
    3. 按第五章完成辅助功能与自动化授权
    4. 在设置中开启「替换系统程序坞」

    说明：当前版本使用开发者本地签名。他人电脑上可能提示「无法验证开发者」，需右键打开。正式对外发布建议申请 Apple Developer ID 并完成公证（Notarization）。
    """,
    font: font(fontName, size: bodySize)
)

page.drawText("八、退出与恢复", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    · 菜单栏 → 退出 RightDock：自动恢复系统程序坞到底部
    · 也可手动选择「恢复系统程序坞（底部）」
    · 开机自启：系统设置 → 通用 → 登录项 → 添加 RightDock.app
    """,
    font: font(fontName, size: bodySize)
)

page.drawText("九、常见问题", font: font(boldName, size: hSize), spacing: 6)
page.drawText(
    """
    Q：点击固定图标无法打开微信 / 飞书？
    A：确认自动化（System Events）已授权。

    Q：Cursor 最大化仍压在 Dock 下？
    A：检查辅助功能是否生效；不要用 ⌃⌘F 原生全屏；在设置中开启「替换系统程序坞」。

    Q：每次重装都要重新授权？
    A：使用稳定签名证书构建（./scripts/install.sh）可减少此问题；授权时请删除旧的重复条目，只保留 /Applications/RightDock.app。
    """,
    font: font(fontName, size: bodySize)
)

pdf.endPDFPage()
pdf.closePDF()

print("PDF: \(pdfPath.path)")
