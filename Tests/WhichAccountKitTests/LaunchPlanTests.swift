import XCTest
@testable import WhichAccountKit

final class LaunchPlanTests: XCTestCase {
    private let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")

    // MARK: argv

    func testProfilePlanOpensANewInstanceWithTheProfileFlag() {
        let plan = LaunchPlan(appURL: chrome, profileDirectory: "Profile 3", url: "https://example.com")
        XCTAssertEqual(plan.openArguments, [
            "-n", "-a", "/Applications/Google Chrome.app",
            "--args", "--profile-directory=Profile 3",
            "https://example.com"
        ])
    }

    func testPassthroughPlanReusesTheRunningBrowser() {
        let plan = LaunchPlan(appURL: chrome, profileDirectory: nil, url: "https://example.com")
        XCTAssertEqual(plan.openArguments, ["-a", "/Applications/Google Chrome.app", "https://example.com"])
    }

    /// No shell is involved, so awkward characters stay inside a single argument.
    func testAwkwardURLStaysOneArgument() {
        let url = #"https://example.com/a b?q="x"&y='$(id)'"#
        let plan = LaunchPlan(appURL: chrome, profileDirectory: nil, url: url)
        XCTAssertEqual(plan.openArguments.last, url)
        XCTAssertEqual(plan.openArguments.count, 3)
    }

    // MARK: running

    func testRunInvokesOpenWithThePlannedArguments() {
        let runner = RecordingRunner()
        let plan = LaunchPlan(appURL: chrome, profileDirectory: "Default", url: "https://example.com")

        XCTAssertTrue(plan.run(using: runner, console: CapturingConsole()))
        XCTAssertEqual(runner.calls, [.init(executable: "/usr/bin/open", arguments: plan.openArguments)])
    }

    func testNonZeroExitIsAFailureAndIsReported() {
        let runner = RecordingRunner()
        runner.status = 1
        let console = CapturingConsole()

        let ok = LaunchPlan(appURL: chrome, profileDirectory: nil, url: "https://example.com")
            .run(using: runner, console: console)

        XCTAssertFalse(ok)
        XCTAssertTrue(console.allErr.contains("exited 1"))
    }

    func testFailureToStartIsAFailureAndIsReported() {
        let runner = RecordingRunner()
        runner.status = nil
        let console = CapturingConsole()

        let ok = LaunchPlan(appURL: chrome, profileDirectory: nil, url: "https://example.com")
            .run(using: runner, console: console)

        XCTAssertFalse(ok)
        XCTAssertTrue(console.allErr.contains("could not start"))
    }

    // MARK: the printed command is safe to paste

    func testPlainArgumentsAreLeftBare() {
        XCTAssertEqual(LaunchPlan.shellQuote("https://example.com/a-b_c"), "https://example.com/a-b_c")
    }

    /// Feed each quoted argument back through a real shell and check it arrives unchanged
    /// and that nothing inside it was executed.
    func testQuotedArgumentsSurviveARealShellUnchanged() throws {
        let nasty = [
            "https://example.com/?q=$(touch /tmp/which-account-pwned)",
            "https://example.com/`id`",
            "it's got a quote",
            #"back\slash and "double quotes""#,
            "Profile 3",
            ""
        ]
        let sentinel = "/tmp/which-account-pwned"
        try? FileManager.default.removeItem(atPath: sentinel)

        for argument in nasty {
            let script = "printf '%s' " + LaunchPlan.shellQuote(argument)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let echoed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(echoed, argument, "round trip changed \(argument)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel), "a quoted argument executed")
    }
}
