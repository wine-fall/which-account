import AppKit
import WhichAccountCore
import WhichAccountKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let command: Command
    private let console: Console = StandardConsole()
    private let runner: ProcessRunner = SystemProcessRunner()

    private lazy var dispatcher = URLDispatcher(
        route: { [unowned self] raw, done in self.route(raw, done: done) },
        finish: { [unowned self] code in self.finish(code) })

    private var router: Router?
    private var picker: PickerController?

    /// If LaunchServices launches us but never delivers a URL, don't linger.
    private let appleEventTimeout: TimeInterval = 10

    init(command: Command) {
        self.command = command
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        switch command {
        case let .route(url):
            dispatcher.enqueue(url)

        case let .showPicker(url, appearance):
            if let appearance {
                NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            }
            showPickerOnly(url)

        case .setup:
            SetupFlow.setup(.live) { self.finish($0) }

        case .restore:
            SetupFlow.restore(.live) { self.finish($0) }

        case .awaitAppleEvent:
            DispatchQueue.main.asyncAfter(deadline: .now() + appleEventTimeout) { [weak self] in
                guard let self, !self.dispatcher.receivedAnyURL else { return }
                self.finish(0)
            }

        case .dryRun, .help, .version, .invalid:
            // Answered in main.swift before AppKit starts.
            finish(0)
        }
    }

    // MARK: URL intake

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }
        dispatcher.enqueue(raw)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            dispatcher.enqueue(url.absoluteString)
        }
    }

    // MARK: routing

    private func route(_ raw: String, done: @escaping (Bool) -> Void) {
        let router = Router(rawURL: raw, environment: .live)
        self.router = router
        if let warning = router.configUnreadableWarning {
            console.err(warning)
        }

        switch router.decision {
        case .passthrough:
            done(handOff(router.plan(profileDirectory: nil), raw: raw))

        case let .openProfile(profile, _):
            done(handOff(router.plan(profileDirectory: profile.directory), raw: raw))

        case let .fallbackSafari(missing):
            Alerts.browserMissing(bundleID: missing)
            done(handOff(router.safariPlan(), raw: raw))

        case let .showPicker(profiles, preselected):
            guard let web = router.webURL else {
                done(true)
                return
            }
            present(profiles: profiles, preselected: preselected, url: web, openForReal: true) {
                done($0)
            }
        }
    }

    private func handOff(_ plan: LaunchPlan?, raw: String) -> Bool {
        guard let plan else {
            console.err("which-account: no browser available for \(raw)")
            return false
        }
        return plan.run(using: runner, console: console)
    }

    /// `--show-picker`: always show the panel, whatever the rules say, and open nothing.
    private func showPickerOnly(_ raw: String) {
        let router = Router(rawURL: raw, environment: .live)
        self.router = router

        guard let web = router.webURL else {
            console.err("which-account: \(raw) is not an http(s) URL")
            finish(2)
            return
        }
        guard !router.profileSet.profiles.isEmpty else {
            console.err("which-account: no Chromium profiles found for \(router.config.browser)")
            finish(2)
            return
        }

        present(profiles: router.profileSet.profiles,
                preselected: router.profileSet.preselectedIndex,
                url: web,
                openForReal: false) { [weak self] succeeded in
            self?.finish(succeeded ? 0 : 1)
        }
    }

    /// Show the picker; `completion` receives whether the hand-off succeeded.
    private func present(profiles: [ChromiumProfile],
                         preselected: Int,
                         url: WebURL,
                         openForReal: Bool,
                         completion: @escaping (Bool) -> Void) {
        let controller = PickerController(profiles: profiles,
                                          preselectedIndex: preselected,
                                          url: url) { [weak self] choice in
            guard let self else { return }
            guard let choice else {
                if !openForReal { self.console.out("cancelled — nothing opened") }
                completion(true)
                return
            }

            var wroteRule = false
            if choice.remember {
                do {
                    try self.router?.remember(host: url.host, profile: choice.profile)
                    wroteRule = true
                } catch {
                    self.console.err("which-account: could not save the rule: \(error.localizedDescription)")
                }
            }

            let plan = self.router?.plan(profileDirectory: choice.profile.directory)
            if openForReal {
                completion(self.handOff(plan, raw: url.absolute))
            } else {
                self.console.out("""
                    chosen      \(choice.profile.title)  [\(choice.profile.directory)]
                    remember    \(wroteRule
                                  ? "yes — rule \"\(url.host)\" -> \(choice.profile.directory) written to "
                                    + (self.router?.configURL.path ?? "config")
                                  : "no")
                    would run   \(plan?.shellCommand ?? "—")
                    """)
                completion(true)
            }
        }
        picker = controller
        controller.show()
    }

    private func finish(_ code: Int32) {
        // Let the current event finish unwinding before the process goes away.
        DispatchQueue.main.async { exit(code) }
    }
}
