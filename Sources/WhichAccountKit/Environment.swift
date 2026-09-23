import Foundation

public enum Constants {
    public static let bundleID = "dev.wine-fall.which-account"
    /// Never "the system default" — that is us, and we would hand the URL to ourselves.
    public static let lastResortBrowser = "com.apple.Safari"
    public static let version = "1.0.4"

    public static let openPath = "/usr/bin/open"
    public static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework"
        + "/Frameworks/LaunchServices.framework/Support/lsregister"

    public static func isOurs(_ bundleID: String) -> Bool {
        bundleID.caseInsensitiveCompare(Self.bundleID) == .orderedSame
    }
}

/// What the app needs from LaunchServices. The real one wraps NSWorkspace; tests
/// supply a fake, so nothing here needs AppKit or a GUI session.
public protocol LaunchServicesClient {
    /// The app installed under this bundle id, if any.
    func appURL(forBundleID bundleID: String) -> URL?
    /// The app currently handling URLs with this scheme.
    func defaultApp(forScheme scheme: String) -> URL?
    /// The bundle id of the app at this location.
    func bundleID(ofAppAt url: URL) -> String?
}

/// Runs a program to completion.
public protocol ProcessRunner {
    /// The exit status, or `nil` when the program could not be started at all.
    func run(_ executable: URL, arguments: [String]) -> Int32?
}

public struct SystemProcessRunner: ProcessRunner {
    /// Discard the program's own output; the caller reports what matters.
    public var quiet: Bool

    public init(quiet: Bool = false) {
        self.quiet = quiet
    }

    public func run(_ executable: URL, arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Where messages go. Tests capture them to assert on what the user would read.
public protocol Console {
    func out(_ text: String)
    func err(_ text: String)
}

public struct StandardConsole: Console {
    public init() {}

    public func out(_ text: String) {
        print(text)
    }

    public func err(_ text: String) {
        FileHandle.standardError.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
    }
}

public enum Paths {
    /// Where to look for the browser's `Local State`.
    ///
    /// `NSHomeDirectory()` ignores `$HOME`, so `WHICH_ACCOUNT_HOME` exists as a
    /// development seam: it lets the picker be driven from a synthetic set of
    /// profiles. Screenshots and manual testing use it so that neither ever has to
    /// be produced from a real person's accounts.
    public static func home(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> URL {
        if let override = environment["WHICH_ACCOUNT_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}
