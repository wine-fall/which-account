import Foundation
import WhichAccountCore

/// The one call that changes a system setting. macOS shows its own confirmation;
/// the completion reports what the user (or the system) decided.
public protocol DefaultBrowserSetter {
    func makeDefault(appURL: URL, completion: @escaping (Error?) -> Void)
}

public struct SetupEnvironment {
    public var launchServices: LaunchServicesClient
    public var setter: DefaultBrowserSetter
    public var runner: ProcessRunner
    public var console: Console
    public var configURL: URL
    /// `Bundle.main.bundleIdentifier` and `Bundle.main.bundleURL` of this process.
    public var bundleID: String?
    public var bundleURL: URL

    public init(launchServices: LaunchServicesClient,
                setter: DefaultBrowserSetter,
                runner: ProcessRunner,
                console: Console,
                configURL: URL,
                bundleID: String?,
                bundleURL: URL) {
        self.launchServices = launchServices
        self.setter = setter
        self.runner = runner
        self.console = console
        self.configURL = configURL
        self.bundleID = bundleID
        self.bundleURL = bundleURL
    }
}

public enum SetupFlow {

    /// The `.app` this process is running inside, or `nil` when it is a bare binary.
    ///
    /// Invoked through a symlink, `Bundle.main` resolves to the directory holding the
    /// symlink and the bundle identifier is `nil` — so registering `Bundle.main.bundleURL`
    /// unchecked would hand `http`/`https` to something like `/opt/homebrew/bin`.
    /// Package wrappers must exec the real path inside the bundle.
    public static func installedBundleURL(bundleID: String?, bundleURL: URL) -> URL? {
        guard let bundleID, Constants.isOurs(bundleID), bundleURL.pathExtension == "app" else {
            return nil
        }
        return bundleURL
    }

    /// True when we already handle both schemes, so there is nothing to ask for.
    public static func isAlreadyDefault(appURL: URL, launchServices: LaunchServicesClient) -> Bool {
        ["http", "https"].allSatisfy { scheme in
            launchServices.defaultApp(forScheme: scheme)?.standardizedFileURL
                == appURL.standardizedFileURL
        }
    }

    /// LaunchServices errors come back as bare sentences like "The file couldn't be
    /// opened". Keep the domain and code so the failure can actually be looked up.
    public static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }

    /// `--setup`: take over as the default browser, recording whoever held the job.
    public static func setup(_ env: SetupEnvironment, completion: @escaping (Int32) -> Void) {
        guard let appURL = installedBundleURL(bundleID: env.bundleID, bundleURL: env.bundleURL) else {
            env.console.err("""
                which-account: this copy is not inside which-account.app, so there is no
                bundle to register as your browser. Run the one in the app bundle:
                  ~/Applications/which-account.app/Contents/MacOS/which-account --setup
                Installed with Homebrew? Run `which-account --setup`; the wrapper in bin
                execs the bundled binary for you.
                """)
            completion(1)
            return
        }

        // LaunchServices does not scan every install location — a Homebrew Cellar,
        // for one — so make sure it knows about this bundle before asking it to be
        // the browser. Registering an app that is already registered is a no-op, and a
        // failure here is not fatal: the call below reports the real problem.
        _ = env.runner.run(URL(fileURLWithPath: Constants.lsregisterPath),
                           arguments: ["-f", appURL.path])

        // Asking to become the default when we already are comes back as an error,
        // which reads like the whole install failed. Say so plainly instead.
        if isAlreadyDefault(appURL: appURL, launchServices: env.launchServices) {
            env.console.out("which-account: already the default handler for http and https — nothing to do.")
            completion(0)
            return
        }

        // Record the browser we are displacing before we displace it, unless the
        // config already names someone other than us.
        let resolver = BrowserResolver(launchServices: env.launchServices)
        var config = ConfigStore.load(at: env.configURL,
                                      fallbackBrowser: resolver.browserForNewConfig())
        if Constants.isOurs(config.browser) {
            config.browser = resolver.browserForNewConfig()
        }

        // Becoming the default browser is only safe once the browser we are displacing
        // is on disk. If that write fails and we took over anyway, there would be no
        // record of where links used to go, and --restore could only guess.
        do {
            try ConfigStore.save(config, to: env.configURL)
        } catch {
            env.console.err("""
                which-account: could not write \(env.configURL.path): \(error.localizedDescription)
                Refusing to become the default browser, because the browser being replaced \
                (\(config.browser)) could not be recorded.
                """)
            completion(1)
            return
        }

        env.console.out("which-account: current browser recorded as \(config.browser)")
        env.console.out("which-account: registering \(appURL.path)")
        if !ChromiumFamily.isChromium(bundleID: config.browser) {
            env.console.out("which-account: \(config.browser) has no profile concept, "
                            + "so which-account will pass every link straight through to it.")
        }

        env.setter.makeDefault(appURL: appURL) { error in
            if let error {
                env.console.err("which-account: could not become the default browser: \(describe(error))")
                completion(1)
            } else {
                env.console.out("which-account: registered as the default handler for http and https.")
                completion(0)
            }
        }
    }

    /// `--restore`: give the default browser back to whoever config names.
    public static func restore(_ env: SetupEnvironment, completion: @escaping (Int32) -> Void) {
        let config = ConfigStore.load(at: env.configURL, fallbackBrowser: Constants.lastResortBrowser)
        let target = Constants.isOurs(config.browser) ? Constants.lastResortBrowser : config.browser

        guard let appURL = env.launchServices.appURL(forBundleID: target) else {
            env.console.err("which-account: \(target) is not installed; set your browser by hand.")
            completion(1)
            return
        }

        env.setter.makeDefault(appURL: appURL) { error in
            if let error {
                env.console.err("which-account: could not restore \(target): \(describe(error))")
                completion(1)
            } else {
                env.console.out("which-account: default browser handed back to \(target).")
                completion(0)
            }
        }
    }
}
