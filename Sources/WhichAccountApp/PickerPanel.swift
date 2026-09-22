import AppKit
import WhichAccountCore

struct PickerChoice {
    let profile: ChromiumProfile
    /// The "Always use this for <host>" box was ticked.
    let remember: Bool
}

/// Borderless panels refuse key status by default; this one needs the keyboard.
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
final class PickerController: NSObject, NSWindowDelegate {
    private let profiles: [ChromiumProfile]
    private let url: WebURL
    private let completion: (PickerChoice?) -> Void

    private var selectedIndex: Int
    private var rows: [ProfileRowView] = []
    private var footer: FooterView!
    private var window: PickerWindow!
    private var finished = false

    init(profiles: [ChromiumProfile],
         preselectedIndex: Int,
         url: WebURL,
         completion: @escaping (PickerChoice?) -> Void) {
        self.profiles = profiles
        self.selectedIndex = min(max(0, preselectedIndex), max(0, profiles.count - 1))
        self.url = url
        self.completion = completion
        super.init()
    }

    // MARK: presentation

    func show() {
        let height = Metrics.panelHeight(rowCount: profiles.count)
        let frame = NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: height)

        window = PickerWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        let root = PickerRootView(frame: frame)
        root.onKeyDown = { [weak self] event in self?.handle(event) ?? false }
        root.onCancel = { [weak self] in self?.finish(nil) }
        buildContents(in: root)
        window.contentView = root

        centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        window.invalidateShadow()
    }

    private func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    private func buildContents(in root: NSView) {
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

        for (index, profile) in profiles.enumerated() {
            let row = ProfileRowView(profile: profile, number: index + 1, width: contentWidth)
            row.frame.origin = NSPoint(x: Metrics.sidePadding, y: y)
            row.isSelected = (index == selectedIndex)
            row.onClick = { [weak self] in self?.choose(index: index) }
            root.addSubview(row)
            rows.append(row)
            y += Metrics.rowHeight + Metrics.rowGap
        }
        y -= Metrics.rowGap
        y += Metrics.sectionGap

        let divider = DividerView(frame: NSRect(x: textX, y: y,
                                                width: textWidth, height: Metrics.dividerHeight))
        root.addSubview(divider)
        y += Metrics.dividerHeight + Metrics.sectionGap

        footer = FooterView(host: url.host, width: textWidth)
        footer.frame.origin = NSPoint(x: textX, y: y)
        footer.onToggle = { [weak self] in
            guard let self else { return }
            self.footer.isChecked.toggle()
        }
        root.addSubview(footer)
    }

    // MARK: input

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: move(by: -1); return true              // up arrow
        case 125: move(by: 1); return true               // down arrow
        case 36, 76: choose(index: selectedIndex); return true  // return, keypad enter
        case 53: finish(nil); return true                // escape
        default: break
        }

        guard let characters = event.charactersIgnoringModifiers,
              let digit = characters.first,
              let value = digit.wholeNumberValue,
              (1...9).contains(value),
              value <= profiles.count else {
            return false
        }
        choose(index: value - 1)
        return true
    }

    private func move(by delta: Int) {
        guard !profiles.isEmpty else { return }
        let count = profiles.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        for (index, row) in rows.enumerated() {
            row.isSelected = (index == selectedIndex)
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

    /// Clicking away means "not now" — the same as escape.
    func windowDidResignKey(_ notification: Notification) {
        finish(nil)
    }
}
