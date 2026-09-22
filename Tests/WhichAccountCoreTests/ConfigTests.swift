import XCTest
@testable import WhichAccountCore

final class ConfigTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("which-account-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testConfigPathHonoursXDGConfigHome() {
        let url = ConfigStore.configURL(environment: ["XDG_CONFIG_HOME": "/custom/cfg"],
                                        home: URL(fileURLWithPath: "/Users/test"))
        XCTAssertEqual(url.path, "/custom/cfg/which-account/config.json")
    }

    func testConfigPathDefaultsToDotConfig() {
        let url = ConfigStore.configURL(environment: [:], home: URL(fileURLWithPath: "/Users/test"))
        XCTAssertEqual(url.path, "/Users/test/.config/which-account/config.json")
    }

    func testEmptyXDGConfigHomeIsIgnored() {
        let url = ConfigStore.configURL(environment: ["XDG_CONFIG_HOME": ""],
                                        home: URL(fileURLWithPath: "/Users/test"))
        XCTAssertEqual(url.path, "/Users/test/.config/which-account/config.json")
    }

    func testLoadCreatesConfigWhenMissing() throws {
        let url = tempDir.appendingPathComponent("which-account/config.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let config = ConfigStore.load(at: url, fallbackBrowser: "com.google.Chrome")

        XCTAssertEqual(config.browser, "com.google.Chrome")
        XCTAssertTrue(config.rules.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRoundTripPreservesCommentsAndRules() throws {
        let url = tempDir.appendingPathComponent("config.json")
        var config = Config.makeDefault(browser: "com.google.Chrome")
        config.rules = [Rule(pattern: "linear.app", profile: "Profile 3", comment: "work")]
        try ConfigStore.save(config, to: url)

        let reloaded = ConfigStore.load(at: url, fallbackBrowser: "com.apple.Safari")
        XCTAssertEqual(reloaded, config)
        XCTAssertEqual(reloaded.rules.first?.comment, "work")

        // The file is readable JSON with the underscore-prefixed comment keys.
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"_comment\""))
        // Slashes in globs and bundle ids are not escaped.
        XCTAssertFalse(text.contains("\\/"))
    }

    func testMalformedConfigIsReplacedWithADefault() throws {
        let url = tempDir.appendingPathComponent("config.json")
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)

        let config = ConfigStore.load(at: url, fallbackBrowser: "com.google.Chrome")
        XCTAssertEqual(config.browser, "com.google.Chrome")
    }

    func testUpsertAddsThenReplacesByPattern() {
        var config = Config.makeDefault(browser: "com.google.Chrome")
        config = ConfigStore.upsertRule(Rule(pattern: "linear.app", profile: "Default"), in: config)
        XCTAssertEqual(config.rules.count, 1)

        config = ConfigStore.upsertRule(Rule(pattern: "LINEAR.APP", profile: "Profile 3"), in: config)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.rules[0].profile, "Profile 3")

        config = ConfigStore.upsertRule(Rule(pattern: "github.com", profile: "Default"), in: config)
        XCTAssertEqual(config.rules.map(\.pattern), ["LINEAR.APP", "github.com"])
    }

    func testRuleKnowsWhetherItIsAGlob() {
        XCTAssertFalse(Rule(pattern: "github.com", profile: "x").isGlob)
        XCTAssertTrue(Rule(pattern: "github.com/*", profile: "x").isGlob)
        XCTAssertTrue(Rule(pattern: "gith?b.com", profile: "x").isGlob)
    }
}
