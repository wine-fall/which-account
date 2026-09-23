import XCTest
import WhichAccountCore
@testable import WhichAccountKit

final class SetupFlowTests: XCTestCase {
    private var tmp: TempDir!
    private var ls: FakeLaunchServices!
    private var setter: FakeSetter!
    private var runner: RecordingRunner!
    private var console: CapturingConsole!

    private let ourApp = URL(fileURLWithPath: Samples.us)

    override func setUp() {
        tmp = TempDir()
        ls = FakeLaunchServices()
        ls.install("com.google.Chrome", at: Samples.chrome)
        ls.install("com.apple.Safari", at: Samples.safari)
        ls.install(Constants.bundleID, at: Samples.us)
        ls.makeDefaultBrowser(URL(fileURLWithPath: Samples.chrome))
        setter = FakeSetter()
        runner = RecordingRunner()
        console = CapturingConsole()
    }

    private func env(bundleID: String? = Constants.bundleID,
                     bundleURL: URL? = nil,
                     configURL: URL? = nil) -> SetupEnvironment {
        SetupEnvironment(launchServices: ls, setter: setter, runner: runner, console: console,
                         configURL: configURL ?? tmp.configURL,
                         bundleID: bundleID, bundleURL: bundleURL ?? ourApp)
    }

    private func runSetup(_ env: SetupEnvironment) -> Int32 {
        var code: Int32 = -1
        SetupFlow.setup(env) { code = $0 }
        return code
    }

    private func runRestore(_ env: SetupEnvironment) -> Int32 {
        var code: Int32 = -1
        SetupFlow.restore(env) { code = $0 }
        return code
    }

    // MARK: refusing to run outside the bundle

    /// Through a symlink, Bundle.main is the symlink's directory and has no bundle id.
    /// Registering that would make /opt/homebrew/bin the "browser".
    func testRefusesWhenInvokedThroughASymlink() {
        let code = runSetup(env(bundleID: nil, bundleURL: URL(fileURLWithPath: "/opt/homebrew/bin")))

        XCTAssertEqual(code, 1)
        XCTAssertTrue(setter.requested.isEmpty, "must not touch the default browser")
        XCTAssertTrue(runner.calls.isEmpty, "must not register anything with LaunchServices")
        XCTAssertTrue(console.allErr.contains("not inside which-account.app"))
    }

    func testRefusesWhenTheBundleIsSomeoneElses() {
        XCTAssertEqual(runSetup(env(bundleID: "com.example.other")), 1)
        XCTAssertTrue(setter.requested.isEmpty)
    }

    func testRefusesABareBinaryEvenWithOurBundleID() {
        let code = runSetup(env(bundleURL: URL(fileURLWithPath: "/tmp/.build/release")))
        XCTAssertEqual(code, 1)
        XCTAssertTrue(setter.requested.isEmpty)
    }

    // MARK: the normal path

    func testRegistersWithLaunchServicesFirst() {
        _ = runSetup(env())
        XCTAssertEqual(runner.calls.first,
                       .init(executable: Constants.lsregisterPath, arguments: ["-f", Samples.us]))
    }

    /// The displaced browser has to be on disk *before* the system is asked to switch,
    /// or --restore would have nothing to restore.
    func testDisplacedBrowserIsOnDiskBeforeTakingOver() {
        var onDiskAtRequest: String?
        setter.onRequest = {
            onDiskAtRequest = ConfigStore.load(at: self.tmp.configURL, fallbackBrowser: "absent").browser
        }

        XCTAssertEqual(runSetup(env()), 0)

        XCTAssertEqual(setter.requested, [ourApp])
        XCTAssertEqual(onDiskAtRequest, "com.google.Chrome")
        XCTAssertTrue(console.allOut.contains("recorded as com.google.Chrome"))
    }

    func testKeepsAnAlreadyRecordedBrowser() throws {
        try tmp.writeConfig(#"{ "browser": "org.mozilla.firefox", "rules": [] }"#)

        XCTAssertEqual(runSetup(env()), 0)

        let saved = ConfigStore.load(at: tmp.configURL, fallbackBrowser: "unused")
        XCTAssertEqual(saved.browser, "org.mozilla.firefox")
    }

    func testReplacesARecordedBrowserThatIsUs() throws {
        try tmp.writeConfig(#"{ "browser": "\#(Constants.bundleID)", "rules": [] }"#)

        _ = runSetup(env())

        let saved = ConfigStore.load(at: tmp.configURL, fallbackBrowser: "unused")
        XCTAssertEqual(saved.browser, "com.google.Chrome")
    }

    func testKeepsExistingRules() throws {
        try tmp.writeConfig("""
            { "browser": "com.google.Chrome",
              "rules": [ { "pattern": "example.com", "profile": "Profile 1" } ] }
            """)

        _ = runSetup(env())

        let saved = ConfigStore.load(at: tmp.configURL, fallbackBrowser: "unused")
        XCTAssertEqual(saved.rules, [Rule(pattern: "example.com", profile: "Profile 1")])
    }

    func testWarnsWhenTheBrowserHasNoProfiles() {
        ls.install("com.apple.Safari", at: Samples.safari)
        ls.makeDefaultBrowser(URL(fileURLWithPath: Samples.safari))

        _ = runSetup(env())

        XCTAssertTrue(console.allOut.contains("no profile concept"))
    }

    // MARK: the paths that must not take over

    /// Asking to become the default when already default is reported by macOS as an
    /// error, which read like the whole install had failed.
    func testAlreadyDefaultSucceedsWithoutAsking() {
        ls.makeDefaultBrowser(ourApp)

        XCTAssertEqual(runSetup(env()), 0)
        XCTAssertTrue(setter.requested.isEmpty)
        XCTAssertTrue(console.allOut.contains("already the default"))
    }

    func testOnlyOneSchemeBeingOursStillAsks() {
        ls.defaults["http"] = ourApp   // https still Chrome

        _ = runSetup(env())

        XCTAssertEqual(setter.requested, [ourApp])
    }

    /// If the displaced browser cannot be written down, taking over would leave
    /// --restore with nothing to restore.
    func testRefusesWhenTheDisplacedBrowserCannotBeRecorded() throws {
        // A plain file where a directory has to be makes every write fail.
        let blocker = tmp.url.appendingPathComponent("blocker")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let unwritable = blocker.appendingPathComponent("which-account/config.json")

        let code = runSetup(env(configURL: unwritable))

        XCTAssertEqual(code, 1)
        XCTAssertTrue(setter.requested.isEmpty, "must not take over without a record")
        XCTAssertTrue(console.allErr.contains("Refusing"))
    }

    func testSystemRefusalIsAFailureWithTheErrorCode() {
        setter.error = NSError(domain: NSCocoaErrorDomain, code: 256,
                               userInfo: [NSLocalizedDescriptionKey: "The file couldn't be opened."])

        XCTAssertEqual(runSetup(env()), 1)
        XCTAssertTrue(console.allErr.contains("NSCocoaErrorDomain 256"))
    }

    // MARK: restore

    func testRestoreHandsBackToTheRecordedBrowser() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)

        XCTAssertEqual(runRestore(env()), 0)
        XCTAssertEqual(setter.requested, [URL(fileURLWithPath: Samples.chrome)])
    }

    func testRestoreNeverHandsBackToUs() throws {
        try tmp.writeConfig(#"{ "browser": "\#(Constants.bundleID)", "rules": [] }"#)

        _ = runRestore(env())

        XCTAssertEqual(setter.requested, [URL(fileURLWithPath: Samples.safari)])
    }

    func testRestoreRefusesWhenTheRecordedBrowserIsGone() throws {
        try tmp.writeConfig(#"{ "browser": "com.brave.Browser", "rules": [] }"#)

        XCTAssertEqual(runRestore(env()), 1)
        XCTAssertTrue(setter.requested.isEmpty)
        XCTAssertTrue(console.allErr.contains("com.brave.Browser is not installed"))
    }

    func testRestoreReportsASystemRefusal() throws {
        try tmp.writeConfig(#"{ "browser": "com.google.Chrome", "rules": [] }"#)
        setter.error = NSError(domain: NSOSStatusErrorDomain, code: -54)

        XCTAssertEqual(runRestore(env()), 1)
        XCTAssertTrue(console.allErr.contains("-54"))
    }
}
