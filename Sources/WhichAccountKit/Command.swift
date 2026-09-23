import Foundation

public enum Appearance: Equatable {
    case light, dark
}

public enum Command: Equatable {
    /// Launched by LaunchServices: wait for the kAEGetURL Apple Event.
    case awaitAppleEvent
    /// A URL on the command line: route it now.
    case route(String)
    case dryRun(String)
    case showPicker(String, appearance: Appearance?)
    case setup
    case restore
    case help
    case version
    /// Bad arguments; the message says why.
    case invalid(String)

    /// Parse the arguments after the program name.
    public static func parse(_ arguments: [String]) -> Command {
        guard let first = arguments.first else { return .awaitAppleEvent }

        func url(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            let value = arguments[index + 1]
            return value.hasPrefix("--") ? nil : value
        }

        switch first {
        case "--help", "-h":
            return .help
        case "--version":
            return .version
        case "--setup":
            return .setup
        case "--restore":
            return .restore
        case "--dry-run":
            guard let url = url(after: first) else { return .invalid("--dry-run needs a URL") }
            return .dryRun(url)
        case "--show-picker":
            guard let url = url(after: first) else { return .invalid("--show-picker needs a URL") }
            var appearance: Appearance?
            if let index = arguments.firstIndex(of: "--appearance") {
                guard index + 1 < arguments.count else {
                    return .invalid("--appearance takes light or dark")
                }
                switch arguments[index + 1].lowercased() {
                case "light": appearance = .light
                case "dark": appearance = .dark
                default: return .invalid("--appearance takes light or dark")
                }
            }
            return .showPicker(url, appearance: appearance)
        default:
            if first.hasPrefix("-") {
                return .invalid("unknown option \(first)")
            }
            return .route(first)
        }
    }
}
