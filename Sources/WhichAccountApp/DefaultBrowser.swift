import AppKit
import WhichAccountCore

/// Changing the default browser is the one thing here that touches system settings.
/// macOS always shows its own confirmation sheet; we never bypass it.
enum DefaultBrowser {

    enum Outcome {
        case confirmed
        case failed(String)
    }

    /// Ask macOS to route http and https to `appURL`. The user still has to say yes.
    ///
    /// `setDefaultApplication(at:toOpenURLsWithScheme:)` is available from macOS 12,
    /// below our deployment target, so every supported system gets this path.
    static func makeDefault(appURL: URL, completion: @escaping (Outcome) -> Void) {
        let workspace = NSWorkspace.shared
        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { httpError in
            if let httpError {
                DispatchQueue.main.async { completion(.failed(describe(httpError))) }
                return
            }
            workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { httpsError in
                DispatchQueue.main.async {
                    if let httpsError {
                        completion(.failed(describe(httpsError)))
                    } else {
                        completion(.confirmed)
                    }
                }
            }
        }
    }

    /// LaunchServices errors come back as bare sentences like "The file couldn't be
    /// opened", which say nothing about what it could not open. Keep the domain and
    /// code, and name the likeliest cause: another bundle registered under our
    /// identifier at a path that no longer exists.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var message = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSOSStatusErrorDomain {
            message += """

                LaunchServices may still have a stale record of \(Constants.bundleID) at a
                path that has been deleted. List them with:
                  \(lsregisterPath) -dump | grep -B30 '\(Constants.bundleID)' | grep path:
                and drop a dead one with:
                  \(lsregisterPath) -u <that path>
                """
        }
        return message
    }

    static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework"
        + "/Frameworks/LaunchServices.framework/Support/lsregister"

    /// The `.app` this process is running inside, or `nil` when it is a bare binary.
    ///
    /// Invoked through a symlink, `Bundle.main` resolves to the directory holding the
    /// symlink and the bundle identifier is `nil` — so registering `Bundle.main.bundleURL`
    /// unchecked would hand `http`/`https` to something like `/opt/homebrew/bin`.
    /// Package wrappers must exec the real path inside the bundle.
    static func installedBundleURL() -> URL? {
        guard Bundle.main.bundleIdentifier == Constants.bundleID,
              Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return Bundle.main.bundleURL
    }

    private static func reportNotInBundle() {
        FileHandle.standardError.write(Data("""
            which-account: this copy is not inside which-account.app, so there is no
            bundle to register as your browser. Run the one in the app bundle:
              ~/Applications/which-account.app/Contents/MacOS/which-account --setup
            Installed with Homebrew? Run `which-account --setup`; the wrapper in bin
            execs the bundled binary for you.

            """.utf8))
    }

    /// True when we already handle both schemes, so there is nothing to ask for.
    static func isAlreadyDefault(appURL: URL) -> Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let probe = URL(string: "\(scheme)://example.com"),
                  let current = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
                return false
            }
            return current.standardizedFileURL == appURL.standardizedFileURL
        }
    }

    /// `--setup`: take over as the default browser, recording whoever held the job.
    static func setup(completion: @escaping (Int32) -> Void) {
        guard let appURL = installedBundleURL() else {
            reportNotInBundle()
            completion(1)
            return
        }

        // Asking to become the default when we already are comes back as an error,
        // which reads like the whole install failed. Say so plainly instead.
        if isAlreadyDefault(appURL: appURL) {
            print("which-account: already the default handler for http and https — nothing to do.")
            completion(0)
            return
        }

        // Record the browser we are displacing before we displace it, unless the
        // config already names someone other than us.
        let configURL = ConfigStore.configURL()
        var config = ConfigStore.load(at: configURL,
                                      fallbackBrowser: BrowserResolver.browserForNewConfig())
        if config.browser.caseInsensitiveCompare(Constants.bundleID) == .orderedSame {
            config.browser = BrowserResolver.browserForNewConfig()
        }

        // Becoming the default browser is only safe once the browser we are displacing
        // is on disk. If that write fails and we took over anyway, there would be no
        // record of where links used to go, and --restore could only guess.
        do {
            try ConfigStore.save(config, to: configURL)
        } catch {
            FileHandle.standardError.write(Data("""
                which-account: could not write \(configURL.path): \
                \(error.localizedDescription)
                Refusing to become the default browser, because the browser being \
                replaced (\(config.browser)) could not be recorded.

                """.utf8))
            completion(1)
            return
        }

        print("which-account: current browser recorded as \(config.browser)")
        print("which-account: registering \(appURL.path)")
        if !ChromiumFamily.isChromium(bundleID: config.browser) {
            print("""
                  which-account: \(config.browser) has no profile concept, so which-account \
                  will pass every link straight through to it.
                  """)
        }

        makeDefault(appURL: appURL) { outcome in
            switch outcome {
            case .confirmed:
                print("which-account: registered as the default handler for http and https.")
                completion(0)
            case let .failed(message):
                FileHandle.standardError.write(
                    Data("which-account: could not become the default browser: \(message)\n".utf8))
                completion(1)
            }
        }
    }

    /// `--restore`: give the default browser back to whoever config names.
    static func restore(completion: @escaping (Int32) -> Void) {
        let configURL = ConfigStore.configURL()
        let config = ConfigStore.load(at: configURL,
                                      fallbackBrowser: Constants.lastResortBrowser)
        var target = config.browser
        if target.caseInsensitiveCompare(Constants.bundleID) == .orderedSame {
            target = Constants.lastResortBrowser
        }

        guard let appURL = BrowserResolver.appURL(forBundleID: target) else {
            FileHandle.standardError.write(
                Data("which-account: \(target) is not installed; set your browser by hand.\n".utf8))
            completion(1)
            return
        }

        makeDefault(appURL: appURL) { outcome in
            switch outcome {
            case .confirmed:
                print("which-account: default browser handed back to \(target).")
                completion(0)
            case let .failed(message):
                FileHandle.standardError.write(
                    Data("which-account: could not restore \(target): \(message)\n".utf8))
                completion(1)
            }
        }
    }

    /// The configured browser has been uninstalled. Say so once, then use Safari.
    static func warnMissing(bundleID: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "which-account can't find your browser"
        alert.informativeText = """
            The config points at \(bundleID), which is not installed. \
            Opening this link in Safari instead.

            Edit "browser" in \(ConfigStore.configURL().path) to point at a browser you have.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
