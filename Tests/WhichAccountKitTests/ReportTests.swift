import XCTest
@testable import WhichAccountKit

final class ReportTests: XCTestCase {
    private var tmp: TempDir!
    private var ls: FakeLaunchServices!

    override func setUp() {
        tmp = TempDir()
        ls = FakeLaunchServices()
        ls.install("com.google.Chrome", at: Samples.chrome)
        ls.install("com.apple.Safari", at: Samples.safari)
    }

    private func report(_ url: String) -> String {
        Report.dryRun(Router(rawURL: url, environment: RouterEnvironment(
            launchServices: ls, configURL: tmp.configURL, home: tmp.home)))
    }

    func testPickerPathNamesThePreselectedProfile() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        try tmp.writeChromeLocalState(Samples.twoProfiles)

        let text = report("https://example.com")

        XCTAssertTrue(text.contains("2 profiles, no rule -> show the picker"))
        XCTAssertTrue(text.contains("Preselect   Profile 1 (work@example.com)"))
        XCTAssertTrue(text.contains("(last used)"))
    }

    func testRulePathPrintsThePasteSafeCommand() throws {
        try tmp.writeConfig("""
            { "browser": "com.google.Chrome",
              "rules": [ { "pattern": "example.com", "profile": "Profile 1" } ] }
            """)
        try tmp.writeChromeLocalState(Samples.twoProfiles)

        let text = report("https://example.com/x")

        XCTAssertTrue(text.contains(#"rule "example.com" matched -> open in Profile 1"#))
        XCTAssertTrue(text.contains(
            "open -n -a '/Applications/Google Chrome.app' --args '--profile-directory=Profile 1' "
            + "https://example.com/x"))
    }

    func testPassthroughAndFallbackPaths() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        XCTAssertTrue(report("mailto:a@example.com").contains("pass through — not an http(s) URL"))

        try tmp.writeConfig(#"{ "browser": "com.brave.Browser", "rules": [] }"#)
        let text = report("https://example.com")
        XCTAssertTrue(text.contains("Installed   NOT FOUND"))
        XCTAssertTrue(text.contains("fall back to Safari"))
        XCTAssertTrue(text.contains("open -a /Applications/Safari.app https://example.com"))
    }

    func testUsageNamesTheVersionAndConfigPath() {
        let text = Report.usage(configPath: "/x/config.json")
        XCTAssertTrue(text.contains(Constants.version))
        XCTAssertTrue(text.contains("/x/config.json"))
    }
}
