import AppKit
import WhichAccountCore

/// One 48px profile row: avatar, email, profile name, and its number key.
final class ProfileRowView: NSView {
    let profile: ChromiumProfile
    /// 1-based, as printed on the key cap. Rows past 9 get no cap.
    let number: Int

    var isSelected: Bool = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    var onClick: (() -> Void)?

    private let titleField: NSTextField
    private let subtitleField: NSTextField

    override var isFlipped: Bool { true }

    init(profile: ChromiumProfile, number: Int, width: CGFloat) {
        self.profile = profile
        self.number = number
        self.titleField = Draw.label(profile.title,
                                     font: .systemFont(ofSize: 13, weight: .medium),
                                     color: Theme.primaryText)
        self.subtitleField = Draw.label(profile.subtitle,
                                        font: .systemFont(ofSize: 11),
                                        color: Theme.secondaryText)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.rowHeight))

        addSubview(titleField)
        addSubview(subtitleField)
        layoutText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var keycaps: [Keycap] {
        var caps: [Keycap] = []
        if isSelected { caps.append(Keycap(text: "\u{21A9}")) }
        if number <= 9 { caps.append(Keycap(text: "\(number)")) }
        return caps
    }

    /// The selected row grows an extra cap, so reserve room for the widest state
    /// and keep the text from reflowing as the selection moves.
    private var reservedKeycapWidth: CGFloat {
        var caps = [Keycap(text: "\u{21A9}")]
        if number <= 9 { caps.append(Keycap(text: "\(number)")) }
        return caps.reduce(0) { $0 + $1.width } + CGFloat(max(0, caps.count - 1)) * Metrics.keycapGap
    }

    private func layoutText() {
        let textX = Metrics.rowPadding + Metrics.avatarSize + Metrics.avatarGap
        let rightEdge = bounds.width - Metrics.rowPadding - reservedKeycapWidth - Metrics.avatarGap
        let textWidth = max(40, rightEdge - textX)

        // Title 16pt line + 1px gap + subtitle 13pt line, centred in the 48px row.
        let blockTop = (Metrics.rowHeight - (16 + 1 + 13)) / 2
        titleField.frame = NSRect(x: textX, y: blockTop, width: textWidth, height: 16)
        subtitleField.frame = NSRect(x: textX, y: blockTop + 17, width: textWidth, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            Theme.selectedRow.setFill()
            NSBezierPath(roundedRect: bounds,
                         xRadius: Metrics.rowRadius,
                         yRadius: Metrics.rowRadius).fill()
        }

        let avatarRect = NSRect(x: Metrics.rowPadding,
                                y: (Metrics.rowHeight - Metrics.avatarSize) / 2,
                                width: Metrics.avatarSize,
                                height: Metrics.avatarSize)
        Draw.avatar(initial: profile.initial,
                    color: Theme.avatarColor(profile.themeColor),
                    in: avatarRect)

        Draw.keycaps(keycaps,
                     rightEdge: bounds.width - Metrics.rowPadding,
                     centerY: bounds.midY)
    }

    /// The picker appears while another app is frontmost, so the very first click
    /// has to act rather than merely activate us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityLabel() -> String? {
        "\(profile.title), \(profile.subtitle)"
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The bottom strip: the remember checkbox on the left, `esc cancel` on the right.
final class FooterView: NSView {
    private let host: String
    private let checkboxLabel: NSTextField

    var isChecked: Bool = false {
        didSet { if isChecked != oldValue { needsDisplay = true } }
    }

    var onToggle: (() -> Void)?

    override var isFlipped: Bool { true }

    init(host: String, width: CGFloat) {
        self.host = host

        let text = NSMutableAttributedString(
            string: "Always use this for ",
            attributes: [.font: NSFont.systemFont(ofSize: 12),
                         .foregroundColor: Theme.primaryText])
        text.append(NSAttributedString(
            string: host,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: Theme.primaryText]))

        self.checkboxLabel = PassthroughTextField(labelWithAttributedString: text)
        self.checkboxLabel.lineBreakMode = .byTruncatingTail
        self.checkboxLabel.cell?.truncatesLastVisibleLine = true
        self.checkboxLabel.setAccessibilityElement(false)

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.footerHeight))
        addSubview(checkboxLabel)
        layoutParts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private let escCap = Keycap(text: "esc")

    private static let cancelFont = NSFont.systemFont(ofSize: 11)

    private var cancelSize: NSSize {
        ("cancel" as NSString).size(withAttributes: [.font: FooterView.cancelFont])
    }

    private var cancelWidth: CGFloat { ceil(cancelSize.width) }

    /// Everything from the box through the end of the label toggles the checkbox.
    private var checkboxHitWidth: CGFloat {
        Metrics.checkboxSize + Metrics.checkboxGap + ceil(checkboxLabel.intrinsicContentSize.width)
    }

    private func layoutParts() {
        let labelX = Metrics.checkboxSize + Metrics.checkboxGap
        let available = max(40, bounds.width - cancelWidth - 6 - escCap.width - 8 - labelX)

        checkboxLabel.frame = NSRect(x: labelX, y: 2,
                                     width: min(ceil(checkboxLabel.intrinsicContentSize.width),
                                                available),
                                     height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0,
                         y: (Metrics.footerHeight - Metrics.checkboxSize) / 2,
                         width: Metrics.checkboxSize,
                         height: Metrics.checkboxSize)
        Draw.checkbox(checked: isChecked, in: box)

        let size = cancelSize
        ("cancel" as NSString).draw(
            at: NSPoint(x: bounds.width - cancelWidth, y: bounds.midY - size.height / 2),
            withAttributes: [.font: FooterView.cancelFont,
                             .foregroundColor: Theme.secondaryText])

        let capRight = bounds.width - cancelWidth - 6
        escCap.draw(in: NSRect(x: capRight - escCap.width,
                               y: (Metrics.footerHeight - Metrics.keycapHeight) / 2,
                               width: escCap.width,
                               height: Metrics.keycapHeight))
    }

    /// The picker appears while another app is frontmost, so the very first click
    /// has to act rather than merely activate us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x <= checkboxHitWidth {
            onToggle?()
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? { "Always use this for \(host)" }
    override func accessibilityValue() -> Any? { isChecked }

    override func accessibilityPerformPress() -> Bool {
        onToggle?()
        return true
    }
}

/// A top-down container, so rows can be positioned from the top like everything else.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A 1px hairline.
final class DividerView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.divider.setFill()
        bounds.fill()
    }
}
