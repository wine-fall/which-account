import AppKit
import WhichAccountCore
import WhichAccountKit

let command = Command.parse(Array(CommandLine.arguments.dropFirst()))
let usage = Report.usage(configPath: ConfigStore.configURL().path)

// Anything that needs no GUI is answered before AppKit starts.
switch command {
case .help:
    print(usage)
    exit(0)
case .version:
    print(Constants.version)
    exit(0)
case let .dryRun(url):
    let router = Router(rawURL: url, environment: .live)
    if let warning = router.configUnreadableWarning {
        StandardConsole().err(warning)
    }
    print(Report.dryRun(router), terminator: "")
    exit(0)
case let .invalid(message):
    StandardConsole().err("which-account: \(message)")
    print(usage)
    exit(2)
default:
    break
}

let app = NSApplication.shared
// No Dock icon, no menu bar: we are a one-shot dialog.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(command: command)
app.delegate = delegate
app.run()
