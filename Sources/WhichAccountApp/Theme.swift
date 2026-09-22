import AppKit

/// Colors from the design canvas, as dynamic NSColors so light/dark follow the system.
///
/// Everything is drawn with NSColor in `draw(_:)` rather than set as a CALayer
/// background, because a CGColor snapshot would not re-resolve when the appearance flips.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    static let panelBackground = dynamic(light: hex(0xF6F6F8), dark: hex(0x2B2B2F))
    static let panelBorder = dynamic(light: hex(0x000000, alpha: 0.14),
                                     dark: hex(0xFFFFFF, alpha: 0.14))

    static let primaryText = dynamic(light: hex(0x1D1D1F), dark: hex(0xF5F5F7))
    static let secondaryText = dynamic(light: hex(0x6E6E73), dark: hex(0x9A9AA0))

    static let selectedRow = dynamic(light: hex(0x000000, alpha: 0.06),
                                     dark: hex(0xFFFFFF, alpha: 0.09))
    static let divider = dynamic(light: hex(0x000000, alpha: 0.09),
                                 dark: hex(0xFFFFFF, alpha: 0.10))

    static let keycapFill = dynamic(light: hex(0xFFFFFF), dark: hex(0x3A3A3F))
    static let keycapBorder = dynamic(light: hex(0x000000, alpha: 0.16),
                                      dark: hex(0xFFFFFF, alpha: 0.16))
    static let keycapText = dynamic(light: hex(0x6E6E73), dark: hex(0xB8B8BE))

    static let checkboxFill = dynamic(light: hex(0xFFFFFF), dark: hex(0x3A3A3F))
    static let checkboxBorder = dynamic(light: hex(0x000000, alpha: 0.28),
                                        dark: hex(0xFFFFFF, alpha: 0.30))
    /// The check itself, in the panel's foreground colour.
    static let checkboxTick = dynamic(light: hex(0x1D1D1F), dark: hex(0xF5F5F7))

    /// Shown when Chrome stores no color for a profile.
    static let avatarFallback = hex(0x8E8E93)

    /// Chrome's profile color, as an NSColor. Same color in both appearances —
    /// it is the profile's identity, not part of our palette.
    static func avatarColor(_ rgb: UInt32?) -> NSColor {
        guard let rgb else { return avatarFallback }
        return hex(rgb)
    }

    /// Chrome lets users pick very pale profile colors, so the letter picks its own
    /// contrast rather than always being white.
    static func avatarTextColor(on background: NSColor) -> NSColor {
        guard let srgb = background.usingColorSpace(.sRGB) else { return .white }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
        return luminance > 0.5 ? hex(0x1D1D1F) : .white
    }
}

/// Fixed measurements from the design canvas.
enum Metrics {
    static let panelWidth: CGFloat = 400
    static let cornerRadius: CGFloat = 14
    static let sidePadding: CGFloat = 12
    /// The header, divider and footer are inset a further 6px inside the side padding.
    static let textInset: CGFloat = 6
    static let topPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 12
    static let sectionGap: CGFloat = 10

    static let titleHeight: CGFloat = 18
    static let headerGap: CGFloat = 3
    static let urlHeight: CGFloat = 15

    static let rowHeight: CGFloat = 48
    static let rowGap: CGFloat = 2
    static let rowRadius: CGFloat = 8
    static let rowPadding: CGFloat = 10

    static let avatarSize: CGFloat = 28
    static let avatarGap: CGFloat = 12

    static let keycapHeight: CGFloat = 20
    static let keycapMinWidth: CGFloat = 20
    static let keycapPadding: CGFloat = 5
    static let keycapGap: CGFloat = 4
    static let keycapRadius: CGFloat = 5

    static let dividerHeight: CGFloat = 1
    static let footerHeight: CGFloat = 20
    static let checkboxSize: CGFloat = 14
    static let checkboxGap: CGFloat = 8

    static var headerHeight: CGFloat { titleHeight + headerGap + urlHeight }

    static func rowsHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowGap
    }

    static func panelHeight(rowCount: Int) -> CGFloat {
        topPadding
            + headerHeight + sectionGap
            + rowsHeight(count: rowCount) + sectionGap
            + dividerHeight + sectionGap
            + footerHeight + bottomPadding
    }
}
