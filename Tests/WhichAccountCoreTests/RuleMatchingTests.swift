import XCTest
@testable import WhichAccountCore

final class GlobTests: XCTestCase {
    func testLiteralAndWildcards() {
        XCTAssertTrue(Glob.matches(pattern: "linear.app", subject: "linear.app"))
        XCTAssertTrue(Glob.matches(pattern: "linear.app/*", subject: "linear.app/acme/issue/OP-1"))
        XCTAssertTrue(Glob.matches(pattern: "*.work.example.com/*", subject: "api.work.example.com/v1/x"))
        XCTAssertTrue(Glob.matches(pattern: "*", subject: "anything at all"))
        XCTAssertTrue(Glob.matches(pattern: "github.com/a?me/*", subject: "github.com/acme/repo"))
    }

    func testNonMatches() {
        XCTAssertFalse(Glob.matches(pattern: "linear.app/*", subject: "linear.app"))
        XCTAssertFalse(Glob.matches(pattern: "linear.app", subject: "notlinear.app"))
        XCTAssertFalse(Glob.matches(pattern: "a?c", subject: "ac"))
    }

    func testStarCrossesSlashes() {
        XCTAssertTrue(Glob.matches(pattern: "github.com/*/pulls", subject: "github.com/a/b/c/pulls"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(Glob.matches(pattern: "LINEAR.app/*", subject: "linear.app/X"))
    }

    func testManyStarsDoNotExplode() {
        let pattern = String(repeating: "*a", count: 24) + "*"
        let subject = String(repeating: "a", count: 200)
        XCTAssertTrue(Glob.matches(pattern: pattern, subject: subject))
    }
}

final class WebURLTests: XCTestCase {
    func testAcceptsHTTPAndHTTPS() {
        XCTAssertEqual(WebURL("https://linear.app/acme/issue/OP-1234")?.host, "linear.app")
        XCTAssertEqual(WebURL("http://example.com")?.host, "example.com")
    }

    func testStripsSchemeAndLoneTrailingSlash() {
        XCTAssertEqual(WebURL("https://linear.app/acme/issue/OP-1234")?.schemeless,
                       "linear.app/acme/issue/OP-1234")
        XCTAssertEqual(WebURL("https://example.com/")?.schemeless, "example.com")
        XCTAssertEqual(WebURL("https://youtube.com/watch?v=abc")?.schemeless, "youtube.com/watch?v=abc")
    }

    func testHostIsLowercased() {
        XCTAssertEqual(WebURL("https://GitHub.COM/login/device")?.host, "github.com")
    }

    func testRejectsNonWebURLs() {
        XCTAssertNil(WebURL(""))
        XCTAssertNil(WebURL("   "))
        XCTAssertNil(WebURL("mailto:someone@example.com"))
        XCTAssertNil(WebURL("file:///etc/hosts"))
        XCTAssertNil(WebURL("ftp://example.com/x"))
        XCTAssertNil(WebURL("just some text"))
    }
}

final class RuleMatcherTests: XCTestCase {
    private func url(_ s: String) -> WebURL { WebURL(s)! }

    func testHostRuleMatchesAnyPathOnThatHost() {
        let rules = [Rule(pattern: "linear.app", profile: "Profile 3")]
        XCTAssertEqual(RuleMatcher.match(url: url("https://linear.app/a/b"), rules: rules)?.profile,
                       "Profile 3")
        XCTAssertNil(RuleMatcher.match(url: url("https://github.com/a"), rules: rules))
    }

    func testHostRuleIsExactNotSuffix() {
        let rules = [Rule(pattern: "work.example.com", profile: "Profile 3")]
        XCTAssertNil(RuleMatcher.match(url: url("https://evil-work.example.com/x"), rules: rules))
        XCTAssertNil(RuleMatcher.match(url: url("https://api.work.example.com/x"), rules: rules))
    }

    func testGlobRuleIsConsideredBeforeHostRule() {
        // The checkbox wrote "github.com"; the user hand-wrote a narrower glob after it.
        let rules = [
            Rule(pattern: "github.com", profile: "Default"),
            Rule(pattern: "github.com/acme/*", profile: "Profile 3")
        ]
        XCTAssertEqual(
            RuleMatcher.match(url: url("https://github.com/acme/repo"), rules: rules)?.profile,
            "Profile 3")
        XCTAssertEqual(
            RuleMatcher.match(url: url("https://github.com/personal/repo"), rules: rules)?.profile,
            "Default")
    }

    func testGlobCanMatchTheFullURLIncludingScheme() {
        let rules = [Rule(pattern: "https://*.work.example.com/*", profile: "Profile 3")]
        XCTAssertEqual(RuleMatcher.match(url: url("https://api.work.example.com/v1"), rules: rules)?.profile,
                       "Profile 3")
    }

    func testNoRulesMatchesNothing() {
        XCTAssertNil(RuleMatcher.match(url: url("https://linear.app"), rules: []))
    }

    func testHostMatchIsCaseInsensitive() {
        let rules = [Rule(pattern: "LINEAR.APP", profile: "Profile 3")]
        XCTAssertNotNil(RuleMatcher.match(url: url("https://linear.app/x"), rules: rules))
    }
}
