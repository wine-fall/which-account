import XCTest
@testable import WhichAccountKit

final class CommandTests: XCTestCase {
    func testNoArgumentsWaitsForLaunchServices() {
        XCTAssertEqual(Command.parse([]), .awaitAppleEvent)
    }

    func testBareURLIsRouted() {
        XCTAssertEqual(Command.parse(["https://example.com"]), .route("https://example.com"))
    }

    func testSimpleFlags() {
        XCTAssertEqual(Command.parse(["--help"]), .help)
        XCTAssertEqual(Command.parse(["-h"]), .help)
        XCTAssertEqual(Command.parse(["--version"]), .version)
        XCTAssertEqual(Command.parse(["--setup"]), .setup)
        XCTAssertEqual(Command.parse(["--restore"]), .restore)
    }

    func testDryRunNeedsAURL() {
        XCTAssertEqual(Command.parse(["--dry-run", "https://example.com"]), .dryRun("https://example.com"))
        XCTAssertEqual(Command.parse(["--dry-run"]), .invalid("--dry-run needs a URL"))
        XCTAssertEqual(Command.parse(["--dry-run", "--setup"]), .invalid("--dry-run needs a URL"))
    }

    func testShowPickerWithAndWithoutAppearance() {
        XCTAssertEqual(Command.parse(["--show-picker", "https://x.example"]),
                       .showPicker("https://x.example", appearance: nil))
        XCTAssertEqual(Command.parse(["--show-picker", "https://x.example", "--appearance", "dark"]),
                       .showPicker("https://x.example", appearance: .dark))
        XCTAssertEqual(Command.parse(["--show-picker", "https://x.example", "--appearance", "LIGHT"]),
                       .showPicker("https://x.example", appearance: .light))
    }

    func testBadAppearanceIsRejected() {
        XCTAssertEqual(Command.parse(["--show-picker", "https://x.example", "--appearance", "blue"]),
                       .invalid("--appearance takes light or dark"))
        XCTAssertEqual(Command.parse(["--show-picker", "https://x.example", "--appearance"]),
                       .invalid("--appearance takes light or dark"))
    }

    func testUnknownOptionIsRejected() {
        XCTAssertEqual(Command.parse(["--frobnicate"]), .invalid("unknown option --frobnicate"))
    }
}
