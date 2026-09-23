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
    /// Development aid: pin the panel to one appearance so both can be reviewed
    /// without flipping the whole system. Unset means follow the system, as shipped.
    private let appearance: NSAppearance.Name?

    /// URLs waiting their turn. LaunchServices delivers to the running process, so a
    /// second link can arrive while the first one's picker is still open; dropping it
    /// would lose the link with no error anywhere.
    private var pending: [String] = []
    private var isRouting = false
    private var receivedAnyURL = false
    /// Non-zero if any hand-off to the browser failed.
    private var exitCode: Int32 = 0

    private var router: Router?
    private var picker: PickerController?

    /// If LaunchServices launches us but never delivers a URL, don't linger.
    private let appleEventTimeout: TimeInterval = 10

    init(mode: Mode, appearance: NSAppearance.Name? = nil) {
        self.mode = mode
        self.appearance = appearance
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance)
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        switch mode {
        case let .route(url):
            enqueue(url)

        case let .showPicker(url):
            showPickerOnly(url)

        case .setup:
            DefaultBrowser.setup { self.finish(Int32($0)) }

        case .restore:
            DefaultBrowser.restore { self.finish(Int32($0)) }

        case .awaitAppleEvent:
            DispatchQueue.main.asyncAfter(deadline: .now() + appleEventTimeout) { [weak self] in
                guard let self, !self.receivedAnyURL else { return }
                self.finish(0)
            }
        }
    }

    // MARK: URL intake

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }
        enqueue(raw)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            enqueue(url.absoluteString)
        }
    }

    private func enqueue(_ raw: String) {
        receivedAnyURL = true
        pending.append(raw)
        routeNextIfIdle()
    }

    private func routeNextIfIdle() {
        guard !isRouting else { return }
        guard !pending.isEmpty else {
            finish(exitCode)
            return
        }
        isRouting = true
        route(pending.removeFirst())
    }

    private func finishedRouting() {
        isRouting = false
        routeNextIfIdle()
    }

    /// Record a failed hand-off so the process does not report success after
    /// silently dropping the URL.
    private func handOff(_ plan: LaunchPlan?, describing raw: String) {
        guard let plan else {
            FileHandle.standardError.write(
                Data("which-account: no browser available for \(raw)\n".utf8))
            exitCode = 1
            return
        }
        if !plan.run() {
            exitCode = 1
        }
    }

    // MARK: routing

    private func route(_ raw: String) {
        let router = Router(rawURL: raw)
        self.router = router
        router.warnIfConfigUnreadable()

        switch router.decision {
        case .passthrough:
            handOff(router.plan(profileDirectory: nil), describing: raw)
            finishedRouting()

        case let .openProfile(profile, _):
            handOff(router.plan(profileDirectory: profile.directory), describing: raw)
            finishedRouting()

        case let .fallbackSafari(missing):
            DefaultBrowser.warnMissing(bundleID: missing)
            handOff(router.safariPlan(), describing: raw)
            finishedRouting()

        case let .showPicker(profiles, preselected):
            guard let web = router.webURL else {
                finishedRouting()
                return
            }
            present(profiles: profiles, preselected: preselected, url: web, openForReal: true)
        }
    }

    /// `--show-picker`: always show the panel, whatever the rules say, and open nothing.
    private func showPickerOnly(_ raw: String) {
        receivedAnyURL = true
        isRouting = true

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
                self.finishedRouting()
                return
            }

            var wroteRule = false
            if choice.remember {
                self.router?.remember(host: url.host, profile: choice.profile)
                wroteRule = true
            }

            if openForReal {
                self.handOff(self.router?.plan(profileDirectory: choice.profile.directory),
                             describing: url.absolute)
            } else {
                self.printChoice(choice, url: url, wroteRule: wroteRule)
            }
            self.finishedRouting()
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
