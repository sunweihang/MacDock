import AppKit

enum ViewSnapshot {
    /// 裁掉与背景色相同的大块留白（README Dock 条截图用）
    static func verticalTrim(_ image: NSBitmapImageRep, background: NSColor, threshold: UInt8 = 6) -> NSBitmapImageRep {
        guard let data = image.bitmapData else { return image }
        let w = image.pixelsWide
        let h = image.pixelsHigh
        let bpr = image.bytesPerRow
        let dataSize = bpr * h
        let bg = background.usingColorSpace(.deviceRGB) ?? background
        var r0 = 0, r1 = h - 1

        func rowIsBg(_ row: Int) -> Bool {
            for x in stride(from: 0, to: w, by: max(1, w / 24)) {
                let o = row * bpr + x * 4
                guard o + 3 < dataSize else { continue }
                if abs(Int(data[o]) - Int(bg.redComponent * 255)) > threshold
                    || abs(Int(data[o + 1]) - Int(bg.greenComponent * 255)) > threshold
                    || abs(Int(data[o + 2]) - Int(bg.blueComponent * 255)) > threshold {
                    return false
                }
            }
            return true
        }

        while r0 < h, rowIsBg(r0) { r0 += 1 }
        while r1 > r0, rowIsBg(r1) { r1 -= 1 }
        let pad = 6
        r0 = max(0, r0 - pad)
        r1 = min(h - 1, r1 + pad)
        let cropH = r1 - r0 + 1
        guard cropH > 0, cropH < h else { return image }

        guard let cg = image.cgImage else { return image }
        let cropRect = CGRect(x: 0, y: h - r1 - 1, width: w, height: cropH)
        guard let sliced = cg.cropping(to: cropRect) else { return image }
        return NSBitmapImageRep(cgImage: sliced)
    }

    @discardableResult
    static func savePNG(of view: NSView, to url: URL, background: NSColor? = nil, trimVertical: Bool = false) -> Bool {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        if let background {
            rep.size = bounds.size
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                background.setFill()
                bounds.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: bounds, to: rep)

        let output: NSBitmapImageRep
        if trimVertical, let background {
            output = verticalTrim(rep, background: background)
        } else {
            output = rep
        }

        guard let data = output.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func savePNG(of window: NSWindow, to url: URL, padding: CGFloat = 0) -> Bool {
        window.displayIfNeeded()
        guard let view = window.contentView else { return false }
        if padding <= 0 {
            return savePNG(of: view, to: url)
        }
        let padded = NSRect(
            x: -padding,
            y: -padding,
            width: view.bounds.width + padding * 2,
            height: view.bounds.height + padding * 2
        )
        let image = NSImage(size: padded.size)
        image.lockFocus()
        NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
        padded.fill()
        view.cacheDisplay(in: CGRect(origin: CGPoint(x: padding, y: padding), size: view.bounds.size), to: view.bitmapImageRepForCachingDisplay(in: view.bounds)!)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
