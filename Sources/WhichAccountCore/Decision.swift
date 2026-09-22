import Foundation

/// Why we are opening the URL without asking.
public enum PassthroughReason: Equatable, Sendable {
    /// Not an http(s) URL (or not a URL at all).
    case notAWebURL
    /// The real browser has no profile concept.
    case browserNotChromium
    /// Exactly one profile — nothing to choose between.
    case singleProfile
    /// No profile at all in Local State (browser never launched).
    case noProfiles
}

public enum Decision: Equatable, Sendable {
    /// Open in the configured browser, letting it pick its own profile.
    case passthrough(reason: PassthroughReason)
    /// Open in a specific profile because a rule said so.
    case openProfile(profile: ChromiumProfile, matchedRule: Rule)
    /// Ask.
    case showPicker(profiles: [ChromiumProfile], preselectedIndex: Int)
    /// The configured browser is gone. Never fall back to "system default" — that is us.
    case fallbackSafari(missingBundleID: String)
}

public struct DecisionInput: Sendable {
    /// The raw URL as handed to us. `nil` when it isn't a routable web URL.
    public let url: WebURL?
    public let rules: [Rule]
    /// `nil` when the configured browser's bundle id resolves to nothing installed.
    public let browser: ChromiumBrowser?
    /// True when the configured browser is installed, whether or not it is Chromium.
    public let browserIsInstalled: Bool
    public let configuredBundleID: String
    public let profileSet: ChromiumProfileSet

    public init(url: WebURL?,
                rules: [Rule],
                browser: ChromiumBrowser?,
                browserIsInstalled: Bool,
                configuredBundleID: String,
                profileSet: ChromiumProfileSet) {
        self.url = url
        self.rules = rules
        self.browser = browser
        self.browserIsInstalled = browserIsInstalled
        self.configuredBundleID = configuredBundleID
        self.profileSet = profileSet
    }
}

public enum DecisionEngine {
    /// The whole routing policy, as one pure function.
    public static func decide(_ input: DecisionInput) -> Decision {
        guard input.browserIsInstalled else {
            return .fallbackSafari(missingBundleID: input.configuredBundleID)
        }
        guard let url = input.url else {
            return .passthrough(reason: .notAWebURL)
        }
        guard input.browser != nil else {
            return .passthrough(reason: .browserNotChromium)
        }

        // A rule wins over everything, but only while the profile it names still exists;
        // a renamed or deleted profile falls through to the picker rather than failing.
        if let rule = RuleMatcher.match(url: url, rules: input.rules),
           let profile = input.profileSet.profile(withDirectory: rule.profile) {
            return .openProfile(profile: profile, matchedRule: rule)
        }

        switch input.profileSet.profiles.count {
        case 0: return .passthrough(reason: .noProfiles)
        case 1: return .passthrough(reason: .singleProfile)
        default:
            return .showPicker(profiles: input.profileSet.profiles,
                               preselectedIndex: input.profileSet.preselectedIndex)
        }
    }
}
