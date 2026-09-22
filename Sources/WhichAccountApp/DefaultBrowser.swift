import AppKit
import WhichAccountCore

/// Changing the default browser is the one thing here that touches system settings.
/// macOS always shows its own confirmation sheet; we never bypass it.
enum DefaultBrowser {

    enum Outcome {
        case confirmed
        case failed(String)
        case unsupportedOS
    }

    /// Ask macOS to route http and https to `appURL`. The user still has to say yes.
    static func makeDefault(appURL: URL, completion: @escaping (Outcome) -> Void) {
        guard #available(macOS 14.0, *) else {
            completion(.unsupportedOS)
            return
        }

        let workspace = NSWorkspace.shared
        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { httpError in
            if let httpError {
                DispatchQueue.main.async { completion(.failed(httpError.localizedDescription)) }
                return
            }
            workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { httpsError in
                DispatchQueue.main.async {
                    if let httpsError {
                        completion(.failed(httpsError.localizedDescription))
                    } else {
                        completion(.confirmed)
                    }
                }
            }
        }
    }

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

    /// `--setup`: take over as the default browser, recording whoever held the job.
    static func setup(completion: @escaping (Int32) -> Void) {
        guard let appURL = installedBundleURL() else {
            reportNotInBundle()
            completion(1)
            return
        }

        // Record the browser we are displacing before we displace it, unless the
        // config already names someone other than us.
        let configURL = ConfigStore.configURL()
        var config = ConfigStore.load(at: configURL,
                                      fallbackBrowser: BrowserResolver.browserForNewConfig())
        if config.browser.caseInsensitiveCompare(Constants.bundleID) == .orderedSame {
            config.browser = BrowserResolver.browserForNewConfig()
            try? ConfigStore.save(config, to: configURL)
        }

        print("which-account: current browser recorded as \(config.browser)")
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
            case .unsupportedOS:
                print("""
                      which-account: on macOS 13 the default browser must be set by hand — \
                      System Settings > Desktop & Dock > Default web browser > which-account.
                      """)
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
            case .unsupportedOS:
                print("""
                      which-account: on macOS 13, set your browser back by hand — \
                      System Settings > Desktop & Dock > Default web browser.
                      """)
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
