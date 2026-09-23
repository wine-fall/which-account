import Foundation
@testable import WhichAccountKit

/// A LaunchServices with a fixed set of installed apps and default handlers.
final class FakeLaunchServices: LaunchServicesClient {
    /// bundle id -> where it is installed
    var installed: [String: URL] = [:]
    /// scheme -> the app currently handling it
    var defaults: [String: URL] = [:]

    func appURL(forBundleID bundleID: String) -> URL? {
        installed.first { $0.key.caseInsensitiveCompare(bundleID) == .orderedSame }?.value
    }

    func defaultApp(forScheme scheme: String) -> URL? {
        defaults[scheme]
    }

    func bundleID(ofAppAt url: URL) -> String? {
        installed.first { $0.value == url }?.key
    }

    /// Install an app and return where it lives.
    @discardableResult
    func install(_ bundleID: String, at path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        installed[bundleID] = url
        return url
    }

    func makeDefaultBrowser(_ url: URL) {
        defaults["http"] = url
        defaults["https"] = url
    }
}

/// Records every program it is asked to run, and answers with a scripted status.
final class RecordingRunner: ProcessRunner {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    /// What `run` returns. `nil` means "could not start".
    var status: Int32? = 0

    func run(_ executable: URL, arguments: [String]) -> Int32? {
        calls.append(Call(executable: executable.path, arguments: arguments))
        return status
    }
}

final class CapturingConsole: Console {
    var stdout: [String] = []
    var stderr: [String] = []

    func out(_ text: String) { stdout.append(text) }
    func err(_ text: String) { stderr.append(text) }

    var allOut: String { stdout.joined(separator: "\n") }
    var allErr: String { stderr.joined(separator: "\n") }
}

/// Stands in for NSWorkspace.setDefaultApplication. Never touches the system.
final class FakeSetter: DefaultBrowserSetter {
    var requested: [URL] = []
    var error: Error?
    /// Called at the moment the request is made, to inspect the state at that point.
    var onRequest: (() -> Void)?

    func makeDefault(appURL: URL, completion: @escaping (Error?) -> Void) {
        requested.append(appURL)
        onRequest?()
        completion(error)
    }
}

/// A scratch directory per test, removed afterwards.
final class TempDir {
    let url: URL

    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("which-account-kit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var configURL: URL {
        url.appendingPathComponent("config/which-account/config.json")
    }

    var home: URL {
        url.appendingPathComponent("home", isDirectory: true)
    }

    /// Write a Chrome `Local State` under `home`.
    func writeChromeLocalState(_ json: String) throws {
        let dir = home.appendingPathComponent("Library/Application Support/Google/Chrome",
                                              isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("Local State"), atomically: true, encoding: .utf8)
    }

    func writeConfig(_ json: String) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try json.write(to: configURL, atomically: true, encoding: .utf8)
    }
}

enum Samples {
    static let chrome = "/Applications/Google Chrome.app"
    static let safari = "/Applications/Safari.app"
    static let firefox = "/Applications/Firefox.app"
    static let us = "/Applications/which-account.app"

    static let twoProfiles = """
    { "profile": { "last_used": "Profile 1", "info_cache": {
        "Default":   { "active_time": 100, "name": "Personal", "user_name": "personal@example.com" },
        "Profile 1": { "active_time": 200, "name": "Work",     "user_name": "work@example.com" } } } }
    """
}
