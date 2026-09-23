import AppKit
import WhichAccountCore
import WhichAccountKit

/// LaunchServices, via NSWorkspace.
struct SystemLaunchServices: LaunchServicesClient {
    func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func defaultApp(forScheme scheme: String) -> URL? {
        guard let probe = URL(string: "\(scheme)://example.com") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    func bundleID(ofAppAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}

/// Asks macOS to route http and https to an app. The user still has to say yes.
///
/// `setDefaultApplication(at:toOpenURLsWithScheme:)` is available from macOS 12,
/// below our deployment target, so every supported system gets this path.
struct WorkspaceDefaultBrowserSetter: DefaultBrowserSetter {
    func makeDefault(appURL: URL, completion: @escaping (Error?) -> Void) {
        let workspace = NSWorkspace.shared
        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { httpError in
            if let httpError {
                DispatchQueue.main.async { completion(httpError) }
                return
            }
            workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { httpsError in
                DispatchQueue.main.async { completion(httpsError) }
            }
        }
    }
}

extension RouterEnvironment {
    static var live: RouterEnvironment {
        RouterEnvironment(launchServices: SystemLaunchServices(),
                          configURL: ConfigStore.configURL(),
                          home: Paths.home())
    }
}

extension SetupEnvironment {
    static var live: SetupEnvironment {
        SetupEnvironment(launchServices: SystemLaunchServices(),
                         setter: WorkspaceDefaultBrowserSetter(),
                         runner: SystemProcessRunner(quiet: true),
                         console: StandardConsole(),
                         configURL: ConfigStore.configURL(),
                         bundleID: Bundle.main.bundleIdentifier,
                         bundleURL: Bundle.main.bundleURL)
    }
}

enum Alerts {
    /// The configured browser has been uninstalled. Say so once, then use Safari.
    static func browserMissing(bundleID: String) {
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
