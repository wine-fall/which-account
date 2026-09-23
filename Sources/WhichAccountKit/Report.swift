import Foundation
import WhichAccountCore

/// `--dry-run`: say exactly what a real run would do, and do none of it.
public enum Report {
    public static func dryRun(_ router: Router) -> String {
        var out = ""
        func line(_ label: String, _ value: String) {
            out += label.padding(toLength: 12, withPad: " ", startingAt: 0) + value + "\n"
        }

        line("URL", router.rawURL)
        line("Host", router.webURL?.host ?? "— not an http(s) URL")

        if let browser = router.browser {
            line("Browser", "\(browser.displayName)  (\(browser.bundleID), Chromium family)")
        } else {
            line("Browser", "\(router.config.browser)  (not a Chromium-family browser)")
        }
        line("Installed", router.appURL?.path ?? "NOT FOUND")
        line("Config", router.configURL.path)

        let profiles = router.profileSet.profiles
        line("Profiles", "\(profiles.count)")
        for (index, profile) in profiles.enumerated() {
            let marker = profile.directory == router.profileSet.lastUsed ? "  (last used)" : ""
            out += "             \(index + 1). \(profile.title)"
                + "  —  \(profile.subtitle)  [\(profile.directory)]\(marker)\n"
        }

        if router.config.rules.isEmpty {
            line("Rules", "none")
        } else {
            line("Rules", "\(router.config.rules.count)")
            for rule in router.config.rules {
                out += "             \(rule.pattern)  ->  \(rule.profile)\n"
            }
        }

        out += "\n"
        switch router.decision {
        case let .openProfile(profile, matchedRule):
            line("Decision", "rule \"\(matchedRule.pattern)\" matched -> "
                 + "open in \(profile.directory) (\(profile.title)), no picker")
            line("Would run", router.plan(profileDirectory: profile.directory)?.shellCommand ?? "—")

        case let .showPicker(pickerProfiles, preselected):
            line("Decision", "\(pickerProfiles.count) profiles, no rule -> show the picker")
            line("Preselect", "\(pickerProfiles[preselected].directory)"
                 + " (\(pickerProfiles[preselected].title))")

        case let .passthrough(reason):
            line("Decision", "pass through — \(describe(reason))")
            line("Would run", router.plan(profileDirectory: nil)?.shellCommand ?? "—")

        case let .fallbackSafari(missing):
            line("Decision", "configured browser \"\(missing)\" is not installed -> "
                 + "warn and fall back to Safari")
            line("Would run", router.safariPlan()?.shellCommand ?? "—")
        }
        return out
    }

    public static func describe(_ reason: PassthroughReason) -> String {
        switch reason {
        case .notAWebURL: return "not an http(s) URL"
        case .browserNotChromium: return "the default browser has no profiles"
        case .singleProfile: return "only one profile"
        case .noProfiles: return "no profiles found in Local State"
        }
    }

    public static func usage(configPath: String) -> String {
        """
        which-account \(Constants.version) — pick the Chrome account a link opens in.

        Normally macOS launches this for you: it registers as the default http/https
        handler, decides which profile the link belongs to, and quits.

        USAGE
          which-account <url>              route a URL now
          which-account --dry-run <url>    print what would happen; open nothing
          which-account --show-picker <url> [--appearance light|dark]
                                           show the panel and print the choice; open nothing
                                           (a ticked checkbox still writes the rule)
          which-account --setup            ask macOS to make this the default browser
          which-account --restore          hand the default browser back to config's `browser`
          which-account --version
          which-account --help

        CONFIG
          \(configPath)
        """
    }
}
