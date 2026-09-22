import Foundation

/// One line of `rules` in config.json.
public struct Rule: Codable, Equatable, Sendable {
    /// Either a bare host ("github.com") or a URL glob ("linear.app/acme/*").
    public let pattern: String
    /// Profile directory name, e.g. "Profile 3".
    public let profile: String
    public var comment: String?

    public init(pattern: String, profile: String, comment: String? = nil) {
        self.pattern = pattern
        self.profile = profile
        self.comment = comment
    }

    enum CodingKeys: String, CodingKey {
        case pattern, profile
        case comment = "_comment"
    }

    /// A pattern with a wildcard is matched against the whole URL; one without
    /// is matched against the host alone.
    public var isGlob: Bool {
        pattern.contains("*") || pattern.contains("?")
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var comment: String?
    /// Bundle id of the browser we hand URLs to — the user's real default browser,
    /// recorded at install time. Never our own bundle id.
    public var browser: String
    public var rules: [Rule]

    public init(comment: String? = nil, browser: String, rules: [Rule] = []) {
        self.comment = comment
        self.browser = browser
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case browser, rules
        case comment = "_comment"
    }

    public static let defaultComment =
        "which-account. 'browser' is the browser URLs are handed to; "
        + "'rules' map a host or a URL glob (* wildcard) to a Chrome profile directory."

    public static func makeDefault(browser: String) -> Config {
        Config(comment: defaultComment, browser: browser, rules: [])
    }
}

public enum ConfigStore {
    /// `$XDG_CONFIG_HOME/which-account/config.json`, defaulting to `~/.config/...`.
    public static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".config", isDirectory: true)
        }
        return base
            .appendingPathComponent("which-account", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// Read the config, creating it with `fallbackBrowser` when it isn't there yet.
    public static func load(at url: URL, fallbackBrowser: String) -> Config {
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        let fresh = Config.makeDefault(browser: fallbackBrowser)
        try? save(fresh, to: url)
        return fresh
    }

    public static func save(_ config: Config, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        var data = try encoder.encode(config)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    /// Add a `host -> profile` rule, replacing any existing rule for the same pattern.
    public static func upsertRule(_ rule: Rule, in config: Config) -> Config {
        var updated = config
        if let i = updated.rules.firstIndex(where: {
            $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
        }) {
            updated.rules[i] = rule
        } else {
            updated.rules.append(rule)
        }
        return updated
    }
}
