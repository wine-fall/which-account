import XCTest
import WhichAccountCore
@testable import WhichAccountKit

final class RouterTests: XCTestCase {
    private var tmp: TempDir!
    private var ls: FakeLaunchServices!

    override func setUp() {
        tmp = TempDir()
        ls = FakeLaunchServices()
        ls.install("com.google.Chrome", at: Samples.chrome)
        ls.install("com.apple.Safari", at: Samples.safari)
        ls.install(Constants.bundleID, at: Samples.us)
    }

    private func router(_ url: String) -> Router {
        Router(rawURL: url,
               environment: RouterEnvironment(launchServices: ls, configURL: tmp.configURL, home: tmp.home))
    }

    // MARK: never route to ourselves

    /// We are the default browser, and there is no config yet. The new config must
    /// not record us as the browser to hand URLs to, or every link would loop.
    func testFreshConfigNeverRecordsUsWhenWeAreTheDefault() {
        ls.makeDefaultBrowser(URL(fileURLWithPath: Samples.us))

        let r = router("https://example.com")

        XCTAssertEqual(r.config.browser, Constants.lastResortBrowser)
        XCTAssertEqual(r.appURL?.path, Samples.safari)
    }

    /// A config edited (or corrupted) to name us must still never hand a URL to us.
    func testConfigNamingUsIsTreatedAsSafari() throws {
        try tmp.writeConfig(#"{ "browser": "\#(Constants.bundleID)", "rules": [] }"#)

        let r = router("https://example.com")

        XCTAssertEqual(r.appURL?.path, Samples.safari)
        XCTAssertNotEqual(r.plan(profileDirectory: nil)?.appURL.path, Samples.us)
    }

    func testBundleIDComparisonIgnoresCase() throws {
        try tmp.writeConfig(#"{ "browser": "DEV.WINE-FALL.WHICH-ACCOUNT", "rules": [] }"#)
        XCTAssertEqual(router("https://example.com").appURL?.path, Samples.safari)
    }

    // MARK: what gets recorded

    func testFreshConfigRecordsTheCurrentDefaultBrowser() throws {
        ls.makeDefaultBrowser(URL(fileURLWithPath: Samples.chrome))

        _ = router("https://example.com")

        let saved = ConfigStore.load(at: tmp.configURL, fallbackBrowser: "unused")
        XCTAssertEqual(saved.browser, "com.google.Chrome")
    }

    // MARK: profiles come from the injected home, not the real one

    func testReadsProfilesFromTheInjectedHome() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        try tmp.writeChromeLocalState(Samples.twoProfiles)

        let r = router("https://example.com")

        XCTAssertEqual(r.profileSet.profiles.map(\.directory), ["Profile 1", "Default"])
        guard case .showPicker = r.decision else {
            return XCTFail("two profiles and no rule should ask, got \(r.decision)")
        }
    }

    func testRuleProducesAPlanForThatProfile() throws {
        try tmp.writeConfig("""
            { "browser": "com.google.Chrome",
              "rules": [ { "pattern": "example.com", "profile": "Profile 1" } ] }
            """)
        try tmp.writeChromeLocalState(Samples.twoProfiles)

        let r = router("https://example.com/x")

        guard case let .openProfile(profile, _) = r.decision else {
            return XCTFail("expected openProfile, got \(r.decision)")
        }
        XCTAssertEqual(r.plan(profileDirectory: profile.directory),
                       LaunchPlan(appURL: URL(fileURLWithPath: Samples.chrome),
                                  profileDirectory: "Profile 1",
                                  url: "https://example.com/x"))
    }

    // MARK: missing browser

    func testUninstalledBrowserFallsBackToSafari() throws {
        try tmp.writeConfig(#"{ "browser": "com.brave.Browser", "rules": [] }"#)

        let r = router("https://example.com")

        XCTAssertEqual(r.decision, .fallbackSafari(missingBundleID: "com.brave.Browser"))
        XCTAssertNil(r.plan(profileDirectory: nil))
        XCTAssertEqual(r.safariPlan()?.appURL.path, Samples.safari)
    }

    // MARK: unreadable config

    func testUnreadableConfigProducesAWarningNamingTheBackup() throws {
        try tmp.writeConfig("{ this is not json")

        let warning = try XCTUnwrap(router("https://example.com").configUnreadableWarning)
        XCTAssertTrue(warning.contains("could not be parsed"))
        XCTAssertTrue(warning.contains("config.invalid-"))
    }

    func testReadableConfigProducesNoWarning() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        XCTAssertNil(router("https://example.com").configUnreadableWarning)
    }

    // MARK: remembering

    func testRememberWritesAHostRuleToDisk() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        var r = router("https://example.com")
        let work = ChromiumProfile(directory: "Profile 1", name: "Work",
                                   userName: nil, themeColor: nil, activeTime: 0)

        try r.remember(host: "example.com", profile: work)

        let saved = ConfigStore.load(at: tmp.configURL, fallbackBrowser: "unused")
        XCTAssertEqual(saved.rules, [Rule(pattern: "example.com", profile: "Profile 1")])
    }
}
