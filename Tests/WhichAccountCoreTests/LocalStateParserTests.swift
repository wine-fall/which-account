import XCTest
@testable import WhichAccountCore

final class LocalStateParserTests: XCTestCase {

    func testParsesBothProfilesMostRecentlyActiveFirst() throws {
        let set = try LocalStateParser.parse(data: Fixtures.twoProfiles)

        XCTAssertEqual(set.profiles.map(\.directory), ["Profile 3", "Default"])
        XCTAssertEqual(set.lastUsed, "Profile 3")
        XCTAssertEqual(set.preselectedIndex, 0)

        let work = set.profiles[0]
        XCTAssertEqual(work.name, "Work")
        XCTAssertEqual(work.userName, "work@example.com")
        XCTAssertTrue(work.isSignedIn)
        XCTAssertEqual(work.title, "work@example.com")
        XCTAssertEqual(work.subtitle, "Work")
        XCTAssertEqual(work.initial, "W")  // first letter of the title line, i.e. the email

        let personal = set.profiles[1]
        XCTAssertEqual(personal.title, "personal@example.com")
        XCTAssertEqual(personal.subtitle, "Personal")
    }

    func testDecodesChromeSignedARGBColors() throws {
        let set = try LocalStateParser.parse(data: Fixtures.twoProfiles)
        // -5715974 as unsigned ARGB is 0xFFA8C7FA -> RGB 0xA8C7FA.
        XCTAssertEqual(set.profiles.first { $0.directory == "Default" }?.themeColor, 0xA8C7FA)
        // -1499549 -> 0xFFE91E63 -> RGB 0xE91E63.
        XCTAssertEqual(set.profiles.first { $0.directory == "Profile 3" }?.themeColor, 0xE91E63)
    }

    func testCountsProfilesThatAreNotSignedIn() throws {
        let set = try LocalStateParser.parse(data: Fixtures.threeProfiles)

        XCTAssertEqual(set.profiles.count, 3)
        // Never activated, so it sorts last.
        let guest = set.profiles[2]
        XCTAssertEqual(guest.directory, "Profile 2")
        XCTAssertFalse(guest.isSignedIn)
        XCTAssertEqual(guest.title, "Profile 2")
        XCTAssertEqual(guest.subtitle, "Not signed in")
        // With no email to show, the avatar falls back to the profile name's letter.
        XCTAssertEqual(guest.initial, "P")
        XCTAssertNil(guest.themeColor)
    }

    /// The fixture deliberately puts `last_used` on the *least* recently active
    /// profile, so returning row 0 unconditionally would fail this.
    func testPreselectionFollowsLastUsedNotRowOrder() throws {
        let set = try LocalStateParser.parse(data: Fixtures.lastUsedIsNotFirstRow)

        XCTAssertEqual(set.profiles.map(\.directory), ["Profile 1", "Default"])
        XCTAssertEqual(set.lastUsed, "Default")
        XCTAssertEqual(set.preselectedIndex, 1)
        XCTAssertEqual(set.profiles[set.preselectedIndex].directory, "Default")
    }

    func testPreselectionFallsBackToFirstRowWhenLastUsedIsUnknown() {
        let set = ChromiumProfileSet(
            profiles: [ChromiumProfile(directory: "Default", name: "a",
                                       userName: nil, themeColor: nil, activeTime: 0)],
            lastUsed: "Profile 9"
        )
        XCTAssertEqual(set.preselectedIndex, 0)
    }

    func testFileWithoutProfileSectionYieldsNoProfiles() throws {
        let set = try LocalStateParser.parse(data: Fixtures.notChromium)
        XCTAssertTrue(set.profiles.isEmpty)
        XCTAssertNil(set.lastUsed)
    }

    func testMissingLocalStateIsNotAnError() {
        let set = LocalStateParser.discover(
            browser: ChromiumFamily.browser(forBundleID: "com.google.Chrome")!,
            home: URL(fileURLWithPath: "/nonexistent-home-for-tests")
        )
        XCTAssertTrue(set.profiles.isEmpty)
    }

    func testLocalStatePathForEachBrowser() {
        let home = URL(fileURLWithPath: "/Users/test")
        let brave = ChromiumFamily.browser(forBundleID: "com.brave.Browser")!
        XCTAssertEqual(
            LocalStateParser.localStateURL(for: brave, home: home).path,
            "/Users/test/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        )
    }

    func testBundleIDLookupIsCaseInsensitiveAndRejectsSafari() {
        XCTAssertNotNil(ChromiumFamily.browser(forBundleID: "com.google.Chrome"))
        XCTAssertNotNil(ChromiumFamily.browser(forBundleID: "COM.GOOGLE.CHROME"))
        XCTAssertNil(ChromiumFamily.browser(forBundleID: "com.apple.Safari"))
        XCTAssertFalse(ChromiumFamily.isChromium(bundleID: "org.mozilla.firefox"))
    }
}
