import Foundation

/// What a key press means to the picker.
public enum PickerKeyAction: Equatable, Sendable {
    /// Move the highlight to this row.
    case move(to: Int)
    /// Open this row and close the panel.
    case choose(index: Int)
    /// Close without opening anything.
    case cancel
    /// Not ours; let AppKit have it.
    case ignore
}

/// The panel's whole keyboard contract, as a pure function so it can be tested
/// without a window, a screen or focus.
public enum PickerKeymap {

    public enum KeyCode {
        public static let returnKey: UInt16 = 36
        public static let keypadEnter: UInt16 = 76
        public static let escape: UInt16 = 53
        public static let arrowUp: UInt16 = 126
        public static let arrowDown: UInt16 = 125
    }

    public static func action(keyCode: UInt16,
                              characters: String?,
                              profileCount: Int,
                              selectedIndex: Int) -> PickerKeyAction {
        guard profileCount > 0 else { return keyCode == KeyCode.escape ? .cancel : .ignore }

        switch keyCode {
        case KeyCode.arrowUp:
            return .move(to: wrap(selectedIndex - 1, count: profileCount))
        case KeyCode.arrowDown:
            return .move(to: wrap(selectedIndex + 1, count: profileCount))
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .choose(index: clamp(selectedIndex, count: profileCount))
        case KeyCode.escape:
            return .cancel
        default:
            break
        }

        // 1-9 pick a row outright. A digit past the last row does nothing, rather
        // than opening some other account by accident.
        guard let digit = characters?.first,
              let value = digit.wholeNumberValue,
              (1...9).contains(value) else {
            return .ignore
        }
        return value <= profileCount ? .choose(index: value - 1) : .ignore
    }

    public static func wrap(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    public static func clamp(_ index: Int, count: Int) -> Int {
        min(max(0, index), count - 1)
    }
}
