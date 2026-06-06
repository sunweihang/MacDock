import AppKit

/// 访达跨应用拖放时的可视反馈：快捷区高亮 + 跟随鼠标的应用图标预览。
@MainActor
final class PinnedDropDragFeedback {
    private let badgePanel = DockDragBadgePanel()
    private weak var zoneView: DockPinnedDragFeedbackView?
    private var cachedPasteboardChangeCount = -1
    private var cachedPreviewIcon: NSImage?

    func attach(zoneView: DockPinnedDragFeedbackView) {
        self.zoneView = zoneView
    }

    func update(draggingApplication: Bool, targeted: Bool, pasteboard: NSPasteboard?) {
        guard draggingApplication else {
            clear()
            return
        }

        let icon = previewIcon(from: pasteboard)
        zoneView?.setTargeting(targeted, previewIcon: icon)

        if pasteboard != nil {
            badgePanel.show(icon: icon, at: NSEvent.mouseLocation)
        } else {
            badgePanel.hide()
        }
    }

    func clear() {
        zoneView?.setTargeting(false, previewIcon: nil)
        badgePanel.hide()
        cachedPasteboardChangeCount = -1
        cachedPreviewIcon = nil
    }

    private func previewIcon(from pasteboard: NSPasteboard?) -> NSImage? {
        guard let pasteboard else {
            return NSImage(systemSymbolName: "app.badge.plus", accessibilityDescription: nil)
        }
        if pasteboard.changeCount != cachedPasteboardChangeCount {
            cachedPasteboardChangeCount = pasteboard.changeCount
            cachedPreviewIcon = nil
            if let path = AppDropPasteboard.applicationURLs(from: pasteboard).first?.path {
                cachedPreviewIcon = NSWorkspace.shared.icon(forFile: path)
            }
        }
        return cachedPreviewIcon
            ?? NSImage(systemSymbolName: "app.badge.plus", accessibilityDescription: nil)
    }
}

// MARK: - 快捷区高亮层

@MainActor
final class DockPinnedDragFeedbackView: NSView {
    private let effectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let hintLabel = NSTextField(labelWithString: "松手添加到快捷方式")
    private let plusBadge = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true

        effectView.material = .selection
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.borderWidth = 2
        effectView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        plusBadge.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
        plusBadge.contentTintColor = .controlAccentColor
        plusBadge.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        plusBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plusBadge)

        hintLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        hintLabel.textColor = .labelColor
        hintLabel.alignment = .center
        hintLabel.maximumNumberOfLines = 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            plusBadge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            plusBadge.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            plusBadge.widthAnchor.constraint(equalToConstant: 24),
            plusBadge.heightAnchor.constraint(equalToConstant: 24),

            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            hintLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setTargeting(_ targeted: Bool, previewIcon: NSImage?) {
        let wasHidden = isHidden
        isHidden = !targeted
        guard targeted else { return }

        iconView.image = previewIcon
        if wasHidden {
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = 1
            }
        }
    }
}

// MARK: - 跟随鼠标的图标徽章

@MainActor
final class DockDragBadgePanel: NSPanel {
    private let iconView = NSImageView()
    private let plusView = NSImageView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        root.layer?.cornerRadius = 14
        root.layer?.borderWidth = 2
        root.layer?.borderColor = NSColor.controlAccentColor.cgColor
        contentView = root

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 10, y: 14, width: 44, height: 44)
        root.addSubview(iconView)

        plusView.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
        plusView.contentTintColor = .controlAccentColor
        plusView.symbolConfiguration = .init(pointSize: 18, weight: .bold)
        plusView.frame = NSRect(x: 40, y: 8, width: 22, height: 22)
        root.addSubview(plusView)
    }

    func show(icon: NSImage?, at screenPoint: NSPoint) {
        iconView.image = icon
        let size: CGFloat = 64
        let origin = NSPoint(
            x: screenPoint.x - size * 0.5,
            y: screenPoint.y - size * 0.5
        )
        setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
