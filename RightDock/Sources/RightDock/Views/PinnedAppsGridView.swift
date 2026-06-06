import AppKit

@MainActor
final class PinnedAppsGridContainer: NSView {
    weak var settings: DockSettings?
    var onPinnedListChanged: (() -> Void)?

    private(set) var cells: [PinnedIconCell] = []

    private let dropTypes = AppDropPasteboard.dragTypes
    private var dragAcceptsApplication = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(dropTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cell(at point: NSPoint) -> PinnedIconCell? {
        guard bounds.contains(point) else { return nil }
        let slop: CGFloat = 2
        for cell in cells where cell.frame.insetBy(dx: -slop, dy: -slop).contains(point) {
            return cell
        }
        return nil
    }

    override var isFlipped: Bool { true }

    func matchesPinned(bundleIds: [String]) -> Bool {
        cells.count == bundleIds.count
            && zip(cells.map(\.bundleIdentifier), bundleIds).allSatisfy(==)
    }

    func refreshAllCells() {
        cells.forEach { $0.refreshAppearance() }
    }

    func setDropHighlight(_ on: Bool) {
        wantsLayer = true
        layer?.borderWidth = on ? 3 : 0
        layer?.borderColor = on ? NSColor.controlAccentColor.cgColor : nil
        layer?.cornerRadius = on ? 10 : 0
        layer?.backgroundColor = on
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : nil
    }

    func reload() {
        cells.forEach { $0.removeFromSuperview() }
        cells.removeAll()

        guard let settings else { return }

        for pinned in settings.pinnedApps {
            let cell = PinnedIconCell(
                pinned: pinned,
                settings: settings
            )
            cell.onActivate = { showAllWindows in
                AppLauncher.activate(pinned: pinned, showAllWindows: showAllWindows)
            }
            cell.onRemove = { [weak self] in
                guard let self, let settings = self.settings else { return }
                settings.removePinned(withId: pinned.id)
                self.reload()
            }
            addSubview(cell)
            cells.append(cell)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let settings else { return }

        let cols = max(1, settings.pinnedColumnCount(innerWidth: bounds.width))
        let size = settings.pinnedSquareSize
        let spacing = settings.pinnedItemSpacing

        for (index, cell) in cells.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = CGFloat(col) * (size + spacing)
            let y = CGFloat(row) * (size + spacing)
            cell.frame = NSRect(x: x, y: y, width: size, height: size)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let hit = super.hitTest(point), hit !== self {
            return hit
        }
        return self
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragAcceptsApplication = AppDropPasteboard.quickAcceptsApplicationDrag(sender.draggingPasteboard)
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !dragAcceptsApplication {
            dragAcceptsApplication = AppDropPasteboard.quickAcceptsApplicationDrag(sender.draggingPasteboard)
        }
        return dragOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragAcceptsApplication = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !AppDropPasteboard.applicationURLs(from: sender.draggingPasteboard).isEmpty
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard dragAcceptsApplication, pointInBounds(sender) else { return [] }
        return .copy
    }

    private func pointInBounds(_ sender: NSDraggingInfo) -> Bool {
        bounds.contains(pointInView(from: sender))
    }

    private func pointInView(from sender: NSDraggingInfo) -> NSPoint {
        guard let window else { return .zero }
        let inWindow = window.convertPoint(fromScreen: sender.draggingLocation)
        return convert(inWindow, from: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let settings else { return false }
        let added = PinnedAppDropper.addApplications(from: sender.draggingPasteboard, settings: settings)
        if added {
            onPinnedListChanged?()
            reload()
        }
        return added
    }
}

@MainActor
final class PinnedIconCell: NSView {
    var bundleIdentifier: String { pinned.bundleIdentifier }
    private let pinned: PinnedApp
    let displayName: String
    private let settings: DockSettings

    var onActivate: ((Bool) -> Void)?
    var onRemove: (() -> Void)?

    private let imageView = NSImageView()
    private let activeBackground = NSView()
    private let runningDot = NSView()

    init(pinned: PinnedApp, settings: DockSettings) {
        self.pinned = pinned
        self.displayName = pinned.displayName
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        activeBackground.wantsLayer = true
        activeBackground.layer?.cornerRadius = 8
        activeBackground.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        activeBackground.isHidden = true
        addSubview(activeBackground)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        runningDot.wantsLayer = true
        runningDot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        runningDot.layer?.cornerRadius = 2.5
        runningDot.isHidden = true
        addSubview(runningDot)

        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        activeBackground.frame = bounds
        let icon = settings.barIconSize
        imageView.frame = NSRect(
            x: (bounds.width - icon) / 2,
            y: (bounds.height - icon) / 2,
            width: icon,
            height: icon
        )
        runningDot.frame = NSRect(x: bounds.width - 8, y: bounds.height - 8, width: 5, height: 5)
    }

    func refreshAppearance() {
        imageView.isHidden = false
        imageView.image = AppLauncher.icon(for: pinned)

        if pinned.isFolderPin {
            activeBackground.isHidden = true
            runningDot.isHidden = true
            imageView.alphaValue = 1
            return
        }

        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == pinned.bundleIdentifier
        }
        let active: Bool = {
            guard running,
                  let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier == pinned.bundleIdentifier else {
                return false
            }
            return true
        }()

        activeBackground.isHidden = !active
        runningDot.isHidden = !running || active
        imageView.alphaValue = running ? 1 : 0.88
    }

    func performActivation(showAllWindows: Bool) {
        refreshAppearance()
        onActivate?(showAllWindows)
    }

    func showContextMenu(with event: NSEvent) {
        refreshAppearance()
        let menu = NSMenu()
        let openTitle = pinned.isFolderPin ? "在访达中打开" : "打开 / 切换到窗口"
        menu.addItem(withTitle: openTitle, action: #selector(menuActivate(_:)), keyEquivalent: "")
        if !pinned.isFolderPin,
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == pinned.bundleIdentifier }) {
            menu.addItem(withTitle: "显示该应用全部窗口", action: #selector(menuActivateAll(_:)), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "从快捷方式移除", action: #selector(menuRemove(_:)), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseUp(with event: NSEvent) {
        performActivation(showAllWindows: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    @objc private func menuActivate(_ sender: Any?) {
        onActivate?(false)
    }

    @objc private func menuActivateAll(_ sender: Any?) {
        onActivate?(true)
    }

    @objc private func menuRemove(_ sender: Any?) {
        onRemove?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
