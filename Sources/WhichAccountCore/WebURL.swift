import Foundation

/// An http(s) URL we are willing to route. Anything else goes straight through.
public struct WebURL: Equatable, Sendable {
    public let absolute: String
    public let host: String
    /// The URL without its scheme, for matching globs and for the panel's subtitle.
    public let schemeless: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        self.absolute = trimmed
        self.host = host.lowercased()

        var rest = trimmed
        if let range = rest.range(of: "://") {
            rest = String(rest[range.upperBound...])
        }
        // A bare host keeps no trailing slash, so "example.com/" reads as "example.com".
        if rest.hasSuffix("/") { rest.removeLast() }
        self.schemeless = rest
    }
}

public enum RuleMatcher {
    /// First matching rule wins. Glob rules are considered before host rules, so a
    /// hand-written `github.com/acme/*` beats a checkbox-written `github.com`.
    public static func match(url: WebURL, rules: [Rule]) -> Rule? {
        for rule in rules where rule.isGlob {
            if Glob.matches(pattern: rule.pattern, subject: url.schemeless)
                || Glob.matches(pattern: rule.pattern, subject: url.absolute) {
                return rule
            }
        }
        for rule in rules where !rule.isGlob {
            if rule.pattern.caseInsensitiveCompare(url.host) == .orderedSame {
                return rule
            }
        }
        return nil
    }
}
