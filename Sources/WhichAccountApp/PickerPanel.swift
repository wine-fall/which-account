import AppKit
import WhichAccountCore

struct PickerChoice {
    let profile: ChromiumProfile
    /// The "Always use this for <host>" box was ticked.
    let remember: Bool
}

/// Borderless panels refuse key status by default; this one needs the keyboard.
///
/// Paired with `.nonactivatingPanel`, this lets the panel take key focus without
/// requiring the process to win activation outright.
final class PickerWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The panel's root view: draws the rounded card and owns the keyboard.
final class PickerRootView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: card,
                                xRadius: Metrics.cornerRadius,
                                yRadius: Metrics.cornerRadius)
        Theme.panelBackground.setFill()
        path.fill()
        Theme.panelBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Builds, shows and drives the picker. One instance per invocation.
final class PickerController: NSObject {
    private let profiles: [ChromiumProfile]
    private let url: WebURL
    private let completion: (PickerChoice?) -> Void

    private var selectedIndex: Int
    private var rows: [ProfileRowView] = []
    private var footer: FooterView!
    private var window: PickerWindow!
    /// Set only when the rows had to be clamped to fit the screen.
    private var rowsScrollView: NSScrollView?
    private var finished = false

    init(profiles: [ChromiumProfile],
         preselectedIndex: Int,
         url: WebURL,
         completion: @escaping (PickerChoice?) -> Void) {
        self.profiles = profiles
        self.selectedIndex = PickerKeymap.clamp(preselectedIndex, count: max(1, profiles.count))
        self.url = url
        self.completion = completion
        super.init()
    }

    // MARK: presentation

    func show() {
        let screen = activeScreen()

        // Enough profiles would otherwise push the footer, and some of the rows,
        // off the bottom of the display. Clamp the row area and let it scroll.
        let margin: CGFloat = 80
        let available = (screen?.visibleFrame.height ?? 800) - margin - Metrics.chromeHeight
        let fullRows = Metrics.rowsHeight(count: profiles.count)
        let visibleRows = max(Metrics.rowHeight, min(fullRows, available))

        let height = Metrics.panelHeight(rowsHeight: visibleRows)
        let frame = NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: height)

        window = PickerWindow(contentRect: frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = PickerRootView(frame: frame)
        root.onKeyDown = { [weak self] event in self?.handle(event) ?? false }
        root.onCancel = { [weak self] in self?.finish(nil) }
        buildContents(in: root, fullRowsHeight: fullRows, visibleRowsHeight: visibleRows)
        window.contentView = root

        centerOn(screen)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        window.invalidateShadow()
    }

    /// Deliberately no dismiss-on-focus-loss: LaunchServices launches us while another
    /// app is frontmost, and a race there would cancel the panel before it is seen.
    /// Escape is the only way to close without opening anything.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func centerOn(_ screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    private func buildContents(in root: NSView,
                               fullRowsHeight: CGFloat,
                               visibleRowsHeight: CGFloat) {
        let contentWidth = Metrics.panelWidth - 2 * Metrics.sidePadding
        let textX = Metrics.sidePadding + Metrics.textInset
        let textWidth = Metrics.panelWidth - 2 * textX

        var y = Metrics.topPadding

        let title = Draw.label("Open in which account?",
                               font: .systemFont(ofSize: 15, weight: .semibold),
                               color: Theme.primaryText)
        title.frame = NSRect(x: textX, y: y, width: textWidth, height: Metrics.titleHeight)
        root.addSubview(title)
        y += Metrics.titleHeight + Metrics.headerGap

        let subtitle = Draw.label(url.schemeless,
                                  font: .systemFont(ofSize: 12),
                                  color: Theme.secondaryText)
        subtitle.frame = NSRect(x: textX, y: y, width: textWidth, height: Metrics.urlHeight)
        root.addSubview(subtitle)
        y += Metrics.urlHeight + Metrics.sectionGap

        let rowsContainer = FlippedView(frame: NSRect(x: 0, y: 0,
                                                     width: contentWidth,
                                                     height: fullRowsHeight))
        var rowY: CGFloat = 0
        for (index, profile) in profiles.enumerated() {
            let row = ProfileRowView(profile: profile, number: index + 1, width: contentWidth)
            row.frame.origin = NSPoint(x: 0, y: rowY)
            row.isSelected = (index == selectedIndex)
            row.onClick = { [weak self] in self?.choose(index: index) }
            rowsContainer.addSubview(row)
            rows.append(row)
            rowY += Metrics.rowHeight + Metrics.rowGap
        }

        let rowsFrame = NSRect(x: Metrics.sidePadding, y: y,
                               width: contentWidth, height: visibleRowsHeight)
        if visibleRowsHeight < fullRowsHeight {
            let scroll = NSScrollView(frame: rowsFrame)
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.documentView = rowsContainer
            root.addSubview(scroll)
            rowsScrollView = scroll
        } else {
            rowsContainer.frame = rowsFrame
            root.addSubview(rowsContainer)
        }
        y += visibleRowsHeight + Metrics.sectionGap

        let divider = DividerView(frame: NSRect(x: textX, y: y,
                                                width: textWidth, height: Metrics.dividerHeight))
        root.addSubview(divider)
        y += Metrics.dividerHeight + Metrics.sectionGap

        footer = FooterView(host: url.host, width: textWidth)
        footer.frame.origin = NSPoint(x: textX, y: y)
        footer.onToggle = { [weak self] in self?.footer.isChecked.toggle() }
        root.addSubview(footer)
    }

    // MARK: input

    private func handle(_ event: NSEvent) -> Bool {
        switch PickerKeymap.action(keyCode: event.keyCode,
                                   characters: event.charactersIgnoringModifiers,
                                   profileCount: profiles.count,
                                   selectedIndex: selectedIndex) {
        case let .move(index):
            select(index)
            return true
        case let .choose(index):
            choose(index: index)
            return true
        case .cancel:
            finish(nil)
            return true
        case .ignore:
            return false
        }
    }

    private func select(_ index: Int) {
        guard profiles.indices.contains(index) else { return }
        selectedIndex = index
        for (position, row) in rows.enumerated() {
            row.isSelected = (position == selectedIndex)
        }
        // Keep the highlight reachable when the list is scrolling.
        if rowsScrollView != nil {
            rows[index].scrollToVisible(rows[index].bounds)
        }
    }

    private func choose(index: Int) {
        guard profiles.indices.contains(index) else { return }
        finish(PickerChoice(profile: profiles[index], remember: footer.isChecked))
    }

    private func finish(_ choice: PickerChoice?) {
        guard !finished else { return }
        finished = true
        window.orderOut(nil)
        completion(choice)
    }
}
