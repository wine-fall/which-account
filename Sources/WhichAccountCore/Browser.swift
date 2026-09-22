import Foundation

/// A Chromium-family browser we know how to drive.
///
/// Every member stores profiles in `~/Library/Application Support/<supportPath>/Local State`
/// and accepts `--profile-directory=<dir>` on the command line.
public struct ChromiumBrowser: Equatable, Sendable {
    public let bundleID: String
    public let displayName: String
    /// Path relative to `~/Library/Application Support`.
    public let supportPath: String

    public init(bundleID: String, displayName: String, supportPath: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.supportPath = supportPath
    }
}

public enum ChromiumFamily {
    /// The browsers v1 supports. Anything else is treated as "no profile concept".
    public static let all: [ChromiumBrowser] = [
        ChromiumBrowser(bundleID: "com.google.chrome",
                        displayName: "Google Chrome",
                        supportPath: "Google/Chrome"),
        ChromiumBrowser(bundleID: "com.google.chrome.beta",
                        displayName: "Google Chrome Beta",
                        supportPath: "Google/Chrome Beta"),
        ChromiumBrowser(bundleID: "com.google.chrome.dev",
                        displayName: "Google Chrome Dev",
                        supportPath: "Google/Chrome Dev"),
        ChromiumBrowser(bundleID: "com.google.chrome.canary",
                        displayName: "Google Chrome Canary",
                        supportPath: "Google/Chrome Canary"),
        ChromiumBrowser(bundleID: "com.microsoft.edgemac",
                        displayName: "Microsoft Edge",
                        supportPath: "Microsoft Edge"),
        ChromiumBrowser(bundleID: "com.microsoft.edgemac.beta",
                        displayName: "Microsoft Edge Beta",
                        supportPath: "Microsoft Edge Beta"),
        ChromiumBrowser(bundleID: "com.brave.browser",
                        displayName: "Brave Browser",
                        supportPath: "BraveSoftware/Brave-Browser"),
        ChromiumBrowser(bundleID: "com.brave.browser.beta",
                        displayName: "Brave Browser Beta",
                        supportPath: "BraveSoftware/Brave-Browser-Beta"),
        ChromiumBrowser(bundleID: "org.chromium.chromium",
                        displayName: "Chromium",
                        supportPath: "Chromium"),
        ChromiumBrowser(bundleID: "com.vivaldi.vivaldi",
                        displayName: "Vivaldi",
                        supportPath: "Vivaldi")
    ]

    /// Look a browser up by bundle id. Bundle ids are case-insensitive on macOS.
    public static func browser(forBundleID bundleID: String) -> ChromiumBrowser? {
        let needle = bundleID.lowercased()
        return all.first { $0.bundleID == needle }
    }

    public static func isChromium(bundleID: String) -> Bool {
        browser(forBundleID: bundleID) != nil
    }
}
