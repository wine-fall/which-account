import Foundation

public enum Glob {
    /// Shell-style wildcard match: `*` matches any run of characters (including `/`),
    /// `?` matches exactly one. Everything else is literal. Case-insensitive.
    ///
    /// Iterative backtracking, so a pattern full of `*` can't blow the stack.
    public static func matches(pattern: String, subject: String) -> Bool {
        let p = Array(pattern.lowercased())
        let s = Array(subject.lowercased())

        var pi = 0, si = 0
        var starP = -1, starS = 0

        while si < s.count {
            // `*` is tested first: a subject that literally contains `*` would
            // otherwise match it by equality and consume the wildcard.
            if pi < p.count && p[pi] == "*" {
                starP = pi
                starS = si
                pi += 1
            } else if pi < p.count && (p[pi] == "?" || p[pi] == s[si]) {
                pi += 1
                si += 1
            } else if starP >= 0 {
                // Backtrack: let the last `*` swallow one more character.
                starS += 1
                si = starS
                pi = starP + 1
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
