import Foundation
import WhichAccountCore

public struct BrowserResolver {
    public let launchServices: LaunchServicesClient

    public init(launchServices: LaunchServicesClient) {
        self.launchServices = launchServices
    }

    /// Bundle id of whatever currently handles https:// — possibly us.
    public func systemDefaultBrowserBundleID() -> String? {
        launchServices.defaultApp(forScheme: "https").flatMap(launchServices.bundleID(ofAppAt:))
    }

    /// The browser a fresh config should point at: the current default, unless that
    /// is already us, in which case Safari.
    public func browserForNewConfig() -> String {
        guard let current = systemDefaultBrowserBundleID(), !Constants.isOurs(current) else {
            return Constants.lastResortBrowser
        }
        return current
    }
}

/// The command we would run, kept as data so `--dry-run` can print exactly what
/// the real run would execute.
public struct LaunchPlan: Equatable {
    public let appURL: URL
    public let profileDirectory: String?
    public let url: String

    public init(appURL: URL, profileDirectory: String?, url: String) {
        self.appURL = appURL
        self.profileDirectory = profileDirectory
        self.url = url
    }

    /// Arguments to `/usr/bin/open`. Each is passed as its own argv entry — no shell is
    /// involved — so a URL or profile name containing spaces or quotes stays intact.
    public var openArguments: [String] {
        var args: [String] = []
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
    public var shellCommand: String {
        (["open"] + openArguments).map(Self.shellQuote).joined(separator: " ")
    }

    static let shellSafe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@")

    public static func shellQuote(_ argument: String) -> String {
        guard argument.contains(where: { !shellSafe.contains($0) }) || argument.isEmpty else {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Returns false when the browser could not be launched. The caller must not
    /// report success in that case: the URL would simply vanish.
    public func run(using runner: ProcessRunner, console: Console) -> Bool {
        switch runner.run(URL(fileURLWithPath: Constants.openPath), arguments: openArguments) {
        case 0?:
            return true
        case let status?:
            console.err("which-account: \(shellCommand) exited \(status)")
            return false
        case nil:
            console.err("which-account: could not start \(Constants.openPath)")
            return false
        }
    }
}

/// Everything `Router` reads from the machine, so tests can supply their own.
public struct RouterEnvironment {
    public var launchServices: LaunchServicesClient
    public var configURL: URL
    public var home: URL

    public init(launchServices: LaunchServicesClient, configURL: URL, home: URL) {
        self.launchServices = launchServices
        self.configURL = configURL
        self.home = home
    }
}

/// Everything the decision engine needs, gathered from this machine.
public struct Router {
    public let configURL: URL
    public private(set) var config: Config
    public let webURL: WebURL?
    public let rawURL: String

    public let browser: ChromiumBrowser?
    public let appURL: URL?
    public let profileSet: ChromiumProfileSet
    public let configOutcome: ConfigStore.LoadOutcome

    private let launchServices: LaunchServicesClient

    public init(rawURL: String, environment: RouterEnvironment) {
        self.rawURL = rawURL
        self.webURL = WebURL(rawURL)
        self.configURL = environment.configURL
        self.launchServices = environment.launchServices

        let resolver = BrowserResolver(launchServices: environment.launchServices)
        let loaded = ConfigStore.loadDetailed(at: environment.configURL,
                                              fallbackBrowser: resolver.browserForNewConfig())
        self.config = loaded.config
        self.configOutcome = loaded.outcome

        // A config that somehow points at us would loop forever; treat it as unset.
        let configured = Constants.isOurs(config.browser) ? Constants.lastResortBrowser
                                                          : config.browser

        self.appURL = environment.launchServices.appURL(forBundleID: configured)
        self.browser = ChromiumFamily.browser(forBundleID: configured)
        self.profileSet = browser.map { LocalStateParser.discover(browser: $0, home: environment.home) }
            ?? ChromiumProfileSet(profiles: [], lastUsed: nil)
    }

    public var decision: Decision {
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
    public func plan(profileDirectory: String?) -> LaunchPlan? {
        guard let appURL else { return nil }
        return LaunchPlan(appURL: appURL, profileDirectory: profileDirectory, url: rawURL)
    }

    public func safariPlan() -> LaunchPlan? {
        guard let safari = launchServices.appURL(forBundleID: Constants.lastResortBrowser) else {
            return nil
        }
        return LaunchPlan(appURL: safari, profileDirectory: nil, url: rawURL)
    }

    /// The warning to show when the config could not be parsed; `nil` otherwise.
    /// Moving it aside silently would leave the user wondering where their rules went.
    public var configUnreadableWarning: String? {
        guard case let .unreadable(backup) = configOutcome else { return nil }
        let where_ = backup.map { "moved to \($0.lastPathComponent)" } ?? "left in place"
        return "which-account: \(configURL.path) could not be parsed, so your rules were "
            + "not applied. The file was \(where_) and a fresh one written. "
            + "Fix the JSON and move it back."
    }

    /// Record `host -> profile` so this host stops asking.
    public mutating func remember(host: String, profile: ChromiumProfile) throws {
        config = ConfigStore.upsertRule(Rule(pattern: host, profile: profile.directory), in: config)
        try ConfigStore.save(config, to: configURL)
    }
}
