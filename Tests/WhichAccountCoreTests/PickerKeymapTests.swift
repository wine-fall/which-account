import XCTest
@testable import WhichAccountCore

final class PickerKeymapTests: XCTestCase {

    private func action(_ keyCode: UInt16,
                        _ characters: String? = nil,
                        count: Int = 3,
                        selected: Int = 0) -> PickerKeyAction {
        PickerKeymap.action(keyCode: keyCode,
                            characters: characters,
                            profileCount: count,
                            selectedIndex: selected)
    }

    func testDigitsOpenThatRowImmediately() {
        XCTAssertEqual(action(18, "1"), .choose(index: 0))
        XCTAssertEqual(action(19, "2"), .choose(index: 1))
        XCTAssertEqual(action(20, "3"), .choose(index: 2))
    }

    func testDigitPastTheLastRowDoesNothing() {
        // Better to ignore it than to open an account the user cannot see.
        XCTAssertEqual(action(21, "4", count: 3), .ignore)
        XCTAssertEqual(action(25, "9", count: 2), .ignore)
    }

    func testZeroIsNotARow() {
        XCTAssertEqual(action(29, "0"), .ignore)
    }

    func testArrowsMoveTheSelection() {
        XCTAssertEqual(action(PickerKeymap.KeyCode.arrowDown, selected: 0), .move(to: 1))
        XCTAssertEqual(action(PickerKeymap.KeyCode.arrowUp, selected: 2), .move(to: 1))
    }

    func testArrowsWrapAtBothEnds() {
        XCTAssertEqual(action(PickerKeymap.KeyCode.arrowUp, count: 3, selected: 0), .move(to: 2))
        XCTAssertEqual(action(PickerKeymap.KeyCode.arrowDown, count: 3, selected: 2), .move(to: 0))
    }

    func testReturnOpensTheSelectedRow() {
        XCTAssertEqual(action(PickerKeymap.KeyCode.returnKey, selected: 1), .choose(index: 1))
        XCTAssertEqual(action(PickerKeymap.KeyCode.keypadEnter, selected: 2), .choose(index: 2))
    }

    func testEscapeCancels() {
        XCTAssertEqual(action(PickerKeymap.KeyCode.escape), .cancel)
        // Even with nothing to choose from, escape still closes the panel.
        XCTAssertEqual(action(PickerKeymap.KeyCode.escape, count: 0), .cancel)
    }

    func testUnrelatedKeysAreLeftToAppKit() {
        XCTAssertEqual(action(48, "\t"), .ignore)       // tab
        XCTAssertEqual(action(49, " "), .ignore)        // space
        XCTAssertEqual(action(0, "a"), .ignore)
        XCTAssertEqual(action(123), .ignore)            // left arrow
    }

    func testOutOfRangeSelectionIsClampedRatherThanCrashing() {
        XCTAssertEqual(action(PickerKeymap.KeyCode.returnKey, count: 2, selected: 7),
                       .choose(index: 1))
    }
}
