import XCTest
@testable import WhichAccountCore

final class DecisionEngineTests: XCTestCase {

    private let chrome = ChromiumFamily.browser(forBundleID: "com.google.Chrome")!

    private func twoProfiles() -> ChromiumProfileSet {
        try! LocalStateParser.parse(data: Fixtures.twoProfiles)
    }

    private func input(url: String?,
                       rules: [Rule] = [],
                       browser: ChromiumBrowser? = nil,
                       installed: Bool = true,
                       bundleID: String = "com.google.Chrome",
                       profiles: ChromiumProfileSet? = nil) -> DecisionInput {
        DecisionInput(
            url: url.flatMap(WebURL.init),
            rules: rules,
            browser: browser ?? chrome,
            browserIsInstalled: installed,
            configuredBundleID: bundleID,
            profileSet: profiles ?? twoProfiles()
        )
    }

    // MARK: the four paths

    func testRuleHitOpensThatProfileSilently() {
        let rules = [Rule(pattern: "linear.app", profile: "Profile 3")]
        let decision = DecisionEngine.decide(input(url: "https://linear.app/x", rules: rules))

        guard case let .openProfile(profile, matchedRule) = decision else {
            return XCTFail("expected openProfile, got \(decision)")
        }
        XCTAssertEqual(profile.directory, "Profile 3")
        XCTAssertEqual(profile.userName, "work@example.com")
        XCTAssertEqual(matchedRule.pattern, "linear.app")
    }

    func testNonChromiumBrowserPassesThrough() {
        let decision = DecisionEngine.decide(
            input(url: "https://linear.app/x", browser: nil, bundleID: "com.apple.Safari"))
        // `browser: nil` in the helper means "use chrome", so build it explicitly.
        _ = decision

        let firefox = DecisionInput(url: WebURL("https://linear.app/x"),
                                    rules: [],
                                    browser: nil,
                                    browserIsInstalled: true,
                                    configuredBundleID: "org.mozilla.firefox",
                                    profileSet: twoProfiles())
        XCTAssertEqual(DecisionEngine.decide(firefox),
                       .passthrough(reason: .browserNotChromium))
    }

    func testSingleProfilePassesThrough() throws {
        let one = try LocalStateParser.parse(data: Fixtures.singleProfile)
        XCTAssertEqual(DecisionEngine.decide(input(url: "https://linear.app/x", profiles: one)),
                       .passthrough(reason: .singleProfile))
    }

    func testNoProfilesPassesThrough() {
        let none = ChromiumProfileSet(profiles: [], lastUsed: nil)
        XCTAssertEqual(DecisionEngine.decide(input(url: "https://linear.app/x", profiles: none)),
                       .passthrough(reason: .noProfiles))
    }

    func testTwoProfilesAndNoRuleShowsPicker() {
        let decision = DecisionEngine.decide(input(url: "https://linear.app/x"))

        guard case let .showPicker(profiles, preselected) = decision else {
            return XCTFail("expected showPicker, got \(decision)")
        }
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[preselected].directory, "Profile 3")
    }

    // MARK: edges

    func testNonWebURLPassesThrough() {
        XCTAssertEqual(DecisionEngine.decide(input(url: "mailto:a@b.com")),
                       .passthrough(reason: .notAWebURL))
        XCTAssertEqual(DecisionEngine.decide(input(url: nil)),
                       .passthrough(reason: .notAWebURL))
        XCTAssertEqual(DecisionEngine.decide(input(url: "")),
                       .passthrough(reason: .notAWebURL))
    }

    func testMissingBrowserFallsBackToSafariNeverToSystemDefault() {
        let decision = DecisionEngine.decide(
            input(url: "https://linear.app/x", installed: false, bundleID: "com.brave.Browser"))
        XCTAssertEqual(decision, .fallbackSafari(missingBundleID: "com.brave.Browser"))
    }

    func testMissingBrowserBeatsEverythingIncludingABadURL() {
        let decision = DecisionEngine.decide(input(url: nil, installed: false))
        XCTAssertEqual(decision, .fallbackSafari(missingBundleID: "com.google.Chrome"))
    }

    /// Local State could not be read at all. The rule names a directory, which is
    /// the only thing the browser actually needs, so it must still be honoured
    /// rather than silently degrading to "open in whatever profile is in front".
    func testRuleIsHonouredWhenLocalStateCouldNotBeRead() {
        let none = ChromiumProfileSet(profiles: [], lastUsed: nil)
        let rules = [Rule(pattern: "linear.app", profile: "Profile 3")]

        let decision = DecisionEngine.decide(
            input(url: "https://linear.app/x", rules: rules, profiles: none))

        guard case let .openProfile(profile, matchedRule) = decision else {
            return XCTFail("expected openProfile, got \(decision)")
        }
        XCTAssertEqual(profile.directory, "Profile 3")
        XCTAssertEqual(matchedRule.pattern, "linear.app")
    }

    func testRuleNamingADeletedProfileFallsThroughToThePicker() {
        let rules = [Rule(pattern: "linear.app", profile: "Profile 9")]
        let decision = DecisionEngine.decide(input(url: "https://linear.app/x", rules: rules))

        guard case .showPicker = decision else {
            return XCTFail("expected showPicker, got \(decision)")
        }
    }

    func testRuleWinsEvenWhenOnlyOneProfileWouldPassThrough() throws {
        let one = try LocalStateParser.parse(data: Fixtures.singleProfile)
        let rules = [Rule(pattern: "linear.app", profile: "Default")]
        guard case .openProfile = DecisionEngine.decide(
            input(url: "https://linear.app/x", rules: rules, profiles: one)) else {
            return XCTFail("a rule should win over the single-profile shortcut")
        }
    }

    /// The whole point of the tool: two accounts on one host that carries no account
    /// information. It must ask every time rather than guess.
    func testSameServiceTwoAccountsAlwaysAsks() {
        for url in ["https://github.com/login/device",
                    "https://accounts.google.com/o/oauth2/auth?response_type=code"] {
            guard case .showPicker = DecisionEngine.decide(input(url: url)) else {
                return XCTFail("\(url) should ask")
            }
        }
    }
}
