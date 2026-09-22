import AppKit
import WhichAccountCore

enum Mode {
    /// A URL on the command line: route it now.
    case route(String)
    /// Launched by LaunchServices: wait for the kAEGetURL Apple Event.
    case awaitAppleEvent
    case showPicker(String)
    case setup
    case restore
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: Mode
    private var router: Router?
    private var picker: PickerController?
    private var handled = false

    /// If LaunchServices launches us but never delivers a URL, don't linger.
    private let appleEventTimeout: TimeInterval = 10

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        switch mode {
        case let .route(url):
            route(url, openForReal: true)

        case let .showPicker(url):
            showPickerOnly(url)

        case .setup:
            DefaultBrowser.setup { self.finish(Int32($0)) }

        case .restore:
            DefaultBrowser.restore { self.finish(Int32($0)) }

        case .awaitAppleEvent:
            DispatchQueue.main.asyncAfter(deadline: .now() + appleEventTimeout) { [weak self] in
                guard let self, !self.handled else { return }
                self.finish(0)
            }
        }
    }

    // MARK: URL intake

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            finish(0)
            return
        }
        route(raw, openForReal: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        route(first.absoluteString, openForReal: true)
    }

    // MARK: routing

    private func route(_ raw: String, openForReal: Bool) {
        guard !handled else { return }
        handled = true

        let router = Router(rawURL: raw)
        self.router = router

        switch router.decision {
        case .passthrough:
            router.plan(profileDirectory: nil)?.run()
            finish(0)

        case let .openProfile(profile, _):
            router.plan(profileDirectory: profile.directory)?.run()
            finish(0)

        case let .fallbackSafari(missing):
            DefaultBrowser.warnMissing(bundleID: missing)
            router.safariPlan()?.run()
            finish(0)

        case let .showPicker(profiles, preselected):
            guard let web = router.webURL else {
                finish(0)
                return
            }
            present(profiles: profiles, preselected: preselected, url: web, openForReal: openForReal)
        }
    }

    /// `--show-picker`: always show the panel, whatever the rules say, and open nothing.
    private func showPickerOnly(_ raw: String) {
        guard !handled else { return }
        handled = true

        let router = Router(rawURL: raw)
        self.router = router

        guard let web = router.webURL else {
            FileHandle.standardError.write(Data("which-account: \(raw) is not an http(s) URL\n".utf8))
            finish(2)
            return
        }
        guard !router.profileSet.profiles.isEmpty else {
            FileHandle.standardError.write(
                Data("which-account: no Chromium profiles found for \(router.config.browser)\n".utf8))
            finish(2)
            return
        }

        present(profiles: router.profileSet.profiles,
                preselected: router.profileSet.preselectedIndex,
                url: web,
                openForReal: false)
    }

    private func present(profiles: [ChromiumProfile],
                         preselected: Int,
                         url: WebURL,
                         openForReal: Bool) {
        let controller = PickerController(profiles: profiles,
                                          preselectedIndex: preselected,
                                          url: url) { [weak self] choice in
            guard let self else { return }
            guard let choice else {
                if !openForReal { print("cancelled — nothing opened") }
                self.finish(0)
                return
            }

            var wroteRule = false
            if choice.remember {
                self.router?.remember(host: url.host, profile: choice.profile)
                wroteRule = true
            }

            if openForReal {
                self.router?.plan(profileDirectory: choice.profile.directory)?.run()
            } else {
                self.printChoice(choice, url: url, wroteRule: wroteRule)
            }
            self.finish(0)
        }
        picker = controller
        controller.show()
    }

    private func printChoice(_ choice: PickerChoice, url: WebURL, wroteRule: Bool) {
        let plan = router?.plan(profileDirectory: choice.profile.directory)
        print("""
              chosen      \(choice.profile.title)  [\(choice.profile.directory)]
              remember    \(wroteRule
                            ? "yes — rule \"\(url.host)\" -> \(choice.profile.directory) written to "
                              + (router?.configURL.path ?? "config")
                            : "no")
              would run   \(plan?.shellCommand ?? "—")
              """)
    }

    private func finish(_ code: Int32) {
        // Let the current event finish unwinding before the process goes away.
        DispatchQueue.main.async { exit(code) }
    }
}
