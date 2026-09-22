import AppKit
import WhichAccountCore

let arguments = Array(CommandLine.arguments.dropFirst())

/// Options that need no GUI are answered and the process exits before AppKit starts.
func urlArgument(after flag: String) -> String {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("which-account: \(flag) needs a URL\n".utf8))
        exit(2)
    }
    return arguments[index + 1]
}

/// `--appearance light|dark` pins the panel's appearance for review.
func appearanceOverride() -> NSAppearance.Name? {
    guard let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count else {
        return nil
    }
    switch arguments[index + 1].lowercased() {
    case "light": return .aqua
    case "dark": return .darkAqua
    default:
        FileHandle.standardError.write(Data("which-account: --appearance takes light or dark\n".utf8))
        exit(2)
    }
}

let mode: Mode

switch arguments.first {
case nil:
    mode = .awaitAppleEvent

case "--help", "-h":
    print(Report.usage)
    exit(0)

case "--version":
    print(Constants.version)
    exit(0)

case "--dry-run":
    Report.dryRun(Router(rawURL: urlArgument(after: "--dry-run")))
    exit(0)

case "--show-picker":
    mode = .showPicker(urlArgument(after: "--show-picker"))

case "--setup":
    mode = .setup

case "--restore":
    mode = .restore

case let first? where first.hasPrefix("-"):
    FileHandle.standardError.write(Data("which-account: unknown option \(first)\n".utf8))
    print(Report.usage)
    exit(2)

case let first?:
    mode = .route(first)
}

let app = NSApplication.shared
// No Dock icon, no menu bar: we are a one-shot dialog.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(mode: mode, appearance: appearanceOverride())
app.delegate = delegate
app.run()
