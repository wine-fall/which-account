import AppKit

/// A key-cap badge: rounded, 1px border all round but 2px along the bottom,
/// so it reads as a physical key.
struct Keycap {
    let text: String

    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    private var textSize: NSSize {
        (text as NSString).size(withAttributes: [.font: Keycap.font])
    }

    var width: CGFloat {
        max(Metrics.keycapMinWidth, ceil(textSize.width) + 2 * Metrics.keycapPadding)
    }

    /// `rect` is the whole cap, `Metrics.keycapHeight` tall.
    func draw(in rect: NSRect) {
        Theme.keycapBorder.setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: Metrics.keycapRadius,
                     yRadius: Metrics.keycapRadius).fill()

        // The face, inset by the border: 1px on three sides, 2px along the bottom.
        let face = NSRect(x: rect.minX + 1,
                          y: rect.minY + 1,
                          width: rect.width - 2,
                          height: rect.height - 3)
        Theme.keycapFill.setFill()
        NSBezierPath(roundedRect: face,
                     xRadius: Metrics.keycapRadius - 1,
                     yRadius: Metrics.keycapRadius - 1).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Keycap.font,
            .foregroundColor: Theme.keycapText
        ]
        let size = textSize
        let origin = NSPoint(x: face.midX - size.width / 2,
                             y: face.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

enum Draw {
    /// Draw a right-aligned run of key caps and return the x they start at.
    @discardableResult
    static func keycaps(_ caps: [Keycap], rightEdge: CGFloat, centerY: CGFloat) -> CGFloat {
        var x = rightEdge
        for cap in caps.reversed() {
            x -= cap.width
            cap.draw(in: NSRect(x: x,
                                y: centerY - Metrics.keycapHeight / 2,
                                width: cap.width,
                                height: Metrics.keycapHeight))
            x -= Metrics.keycapGap
        }
        return x + Metrics.keycapGap
    }

    /// The circular profile avatar: Chrome's own profile color with the profile's initial.
    static func avatar(initial: String, color: NSColor, in rect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.avatarTextColor(on: color)
        ]
        let size = (initial as NSString).size(withAttributes: attributes)
        (initial as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2,
                                               y: rect.midY - size.height / 2),
                                   withAttributes: attributes)
    }

    /// The box never fills: ticking it makes the check appear, nothing else.
    /// Keeps the panel free of any colour that would outshout the account rows.
    static func checkbox(checked: Bool, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 3.5, yRadius: 3.5)
        Theme.checkboxFill.setFill()
        path.fill()
        Theme.checkboxBorder.setStroke()
        path.lineWidth = 1
        path.stroke()

        guard checked else { return }

        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7.2))
        tick.line(to: NSPoint(x: rect.minX + 5.6, y: rect.minY + 9.8))
        tick.line(to: NSPoint(x: rect.minX + 11, y: rect.minY + 4.4))
        tick.lineWidth = 1.8
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        Theme.checkboxTick.setStroke()
        tick.stroke()
    }

    /// A non-editable label that truncates with an ellipsis, like the design shows.
    ///
    /// Click-through: a label sitting on a row must not swallow the click that
    /// picks that row, and the row — not its two lines of text — is the thing
    /// VoiceOver should announce.
    static func label(_ text: String,
                      font: NSFont,
                      color: NSColor,
                      alignment: NSTextAlignment = .left) -> NSTextField {
        let field = PassthroughTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.isSelectable = false
        field.setAccessibilityElement(false)
        return field
    }
}

/// A label that is invisible to both the mouse and the accessibility hit test,
/// so the view behind it stays the clickable thing.
final class PassthroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { nil }
}
