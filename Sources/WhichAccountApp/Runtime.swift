import AppKit
import WhichAccountCore

enum Constants {
    static let bundleID = "dev.wine-fall.which-account"
    /// Never "the system default" — that is us, and we would hand the URL to ourselves.
    static let lastResortBrowser = "com.apple.Safari"
    static let version = "1.0.3"
}

enum BrowserResolver {
    /// Bundle id of whatever currently handles https:// — possibly us.
    static func systemDefaultBrowserBundleID() -> String? {
        guard let probe = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    /// The browser a fresh config should point at: the current default, unless that is
    /// already us, in which case Safari.
    static func browserForNewConfig() -> String {
        guard let current = systemDefaultBrowserBundleID(),
              current.caseInsensitiveCompare(Constants.bundleID) != .orderedSame else {
            return Constants.lastResortBrowser
        }
        return current
    }

    static func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// The command we would run, kept as data so `--dry-run` can print exactly what
/// the real run would execute.
struct LaunchPlan {
    let appURL: URL
    let profileDirectory: String?
    let url: String

    var arguments: [String] {
        var args = ["open"]
        if profileDirectory != nil {
            // A new instance is required to pass --args; Chrome forwards it to the
            // running copy and exits.
            args.append("-n")
        }
        args.append(contentsOf: ["-a", appURL.path])
        if let profileDirectory {
            args.append(contentsOf: ["--args", "--profile-directory=\(profileDirectory)"])
        }
        args.append(url)
        return args
    }

    /// Single-quoted, because this line is printed for people to copy. Double quotes
    /// would leave `$`, backticks and backslashes live, so a URL containing `$(id)`
    /// would run a command when pasted.
    var shellCommand: String {
        arguments.map { argument in
            guard argument.contains(where: { !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@".contains($0) }) else {
                return argument
            }
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    /// Returns false when the browser could not be launched. The caller must not
    /// report success in that case: the URL would simply vanish.
    @discardableResult
    func run() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = Array(arguments.dropFirst())
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                FileHandle.standardError.write(Data(
                    "which-account: \(shellCommand) exited \(process.terminationStatus)\n".utf8))
                return false
            }
            return true
        } catch {
            FileHandle.standardError.write(
                Data("which-account: failed to launch browser: \(error)\n".utf8))
            return false
        }
    }
}

/// Everything the decision engine needs, gathered from this machine.
struct Router {
    let configURL: URL
    var config: Config
    let webURL: WebURL?
    let rawURL: String

    let browser: ChromiumBrowser?
    let appURL: URL?
    let profileSet: ChromiumProfileSet
    let configOutcome: ConfigStore.LoadOutcome

    init(rawURL: String) {
        self.rawURL = rawURL
        self.webURL = WebURL(rawURL)
        self.configURL = ConfigStore.configURL()
        let loaded = ConfigStore.loadDetailed(at: configURL,
                                              fallbackBrowser: BrowserResolver.browserForNewConfig())
        self.config = loaded.config
        self.configOutcome = loaded.outcome

        // A config that somehow points at us would loop forever; treat it as unset.
        let configured = config.browser.caseInsensitiveCompare(Constants.bundleID) == .orderedSame
            ? Constants.lastResortBrowser
            : config.browser

        self.appURL = BrowserResolver.appURL(forBundleID: configured)
        self.browser = ChromiumFamily.browser(forBundleID: configured)
        self.profileSet = browser.map { LocalStateParser.discover(browser: $0, home: Router.home) }
            ?? ChromiumProfileSet(profiles: [], lastUsed: nil)
    }

    var decision: Decision {
        DecisionEngine.decide(DecisionInput(
            url: webURL,
            rules: config.rules,
            browser: browser,
            browserIsInstalled: appURL != nil,
            configuredBundleID: config.browser,
            profileSet: profileSet
        ))
    }

    /// Where the URL actually goes, given a decision.
    func plan(profileDirectory: String?) -> LaunchPlan? {
        guard let appURL else { return nil }
        return LaunchPlan(appURL: appURL, profileDirectory: profileDirectory, url: rawURL)
    }

    func safariPlan() -> LaunchPlan? {
        guard let safari = BrowserResolver.appURL(forBundleID: Constants.lastResortBrowser) else {
            return nil
        }
        return LaunchPlan(appURL: safari, profileDirectory: nil, url: rawURL)
    }

    /// Say so when the config could not be parsed. Moving it aside silently would
    /// leave the user wondering where their rules went.
    func warnIfConfigUnreadable() {
        guard case let .unreadable(backup) = configOutcome else { return }
        let where_ = backup.map { "moved to \($0.lastPathComponent)" } ?? "left in place"
        FileHandle.standardError.write(Data("""
            which-account: \(configURL.path) could not be parsed, so your rules were \
            not applied. The file was \(where_) and a fresh one written. \
            Fix the JSON and move it back.

            """.utf8))
    }

    /// Where to look for the browser's `Local State`.
    ///
    /// `NSHomeDirectory()` ignores `$HOME`, so `WHICH_ACCOUNT_HOME` exists as a
    /// development seam: it lets the picker be driven from a synthetic set of
    /// profiles. Screenshots and manual testing use it so that neither ever has to
    /// be produced from a real person's accounts.
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["WHICH_ACCOUNT_HOME"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Record `host -> profile` so this host stops asking.
    mutating func remember(host: String, profile: ChromiumProfile) {
        config = ConfigStore.upsertRule(Rule(pattern: host, profile: profile.directory),
                                        in: config)
        do {
            try ConfigStore.save(config, to: configURL)
        } catch {
            FileHandle.standardError.write(
                Data("which-account: could not write \(configURL.path): \(error)\n".utf8))
        }
    }
}
