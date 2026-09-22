import AppKit
import WhichAccountCore

enum Constants {
    static let bundleID = "dev.wine-fall.which-account"
    /// Never "the system default" — that is us, and we would hand the URL to ourselves.
    static let lastResortBrowser = "com.apple.Safari"
    static let version = "1.0.0"
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

    var shellCommand: String {
        arguments.map { argument in
            argument.contains(where: { " \"'$&|;()<>*?".contains($0) })
                ? "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
                : argument
        }.joined(separator: " ")
    }

    @discardableResult
    func run() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = Array(arguments.dropFirst())
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
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

    init(rawURL: String) {
        self.rawURL = rawURL
        self.webURL = WebURL(rawURL)
        self.configURL = ConfigStore.configURL()
        self.config = ConfigStore.load(at: configURL,
                                       fallbackBrowser: BrowserResolver.browserForNewConfig())

        // A config that somehow points at us would loop forever; treat it as unset.
        let configured = config.browser.caseInsensitiveCompare(Constants.bundleID) == .orderedSame
            ? Constants.lastResortBrowser
            : config.browser

        self.appURL = BrowserResolver.appURL(forBundleID: configured)
        self.browser = ChromiumFamily.browser(forBundleID: configured)
        self.profileSet = browser.map { LocalStateParser.discover(browser: $0) }
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
