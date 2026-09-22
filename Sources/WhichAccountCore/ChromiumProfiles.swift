import Foundation

/// One Chrome profile as `Local State` describes it.
public struct ChromiumProfile: Equatable, Sendable {
    /// Directory name under the browser's user-data dir: "Default", "Profile 3", ...
    /// This is what goes into `--profile-directory=`.
    public let directory: String
    /// The profile's display name, e.g. "Work" or "Personal".
    public let name: String
    /// The signed-in account, e.g. "work@example.com". Empty/missing means not signed in.
    public let userName: String?
    /// Chrome's own theme color for this profile, as 0xRRGGBB. `nil` when Chrome stores none.
    public let themeColor: UInt32?
    /// Last time Chrome activated this profile; used only for ordering.
    public let activeTime: Double

    public init(directory: String,
                name: String,
                userName: String?,
                themeColor: UInt32?,
                activeTime: Double) {
        self.directory = directory
        self.name = name
        self.userName = userName
        self.themeColor = themeColor
        self.activeTime = activeTime
    }

    public var isSignedIn: Bool {
        guard let userName else { return false }
        return !userName.isEmpty
    }

    /// Title line in the picker: the email when signed in, else the profile name.
    public var title: String {
        isSignedIn ? userName! : name
    }

    /// Subtitle line in the picker.
    public var subtitle: String {
        isSignedIn ? name : "Not signed in"
    }

    /// The letter drawn inside the avatar circle: the first letter of whatever the
    /// row's title line shows, so a signed-in row reads as its email.
    public var initial: String {
        guard let first = title.first else { return "?" }
        return String(first).uppercased()
    }
}

/// What `Local State` told us.
public struct ChromiumProfileSet: Equatable, Sendable {
    /// Ordered for display: most recently active first.
    public let profiles: [ChromiumProfile]
    /// Directory name of the profile Chrome used last; the picker preselects it.
    public let lastUsed: String?

    public init(profiles: [ChromiumProfile], lastUsed: String?) {
        self.profiles = profiles
        self.lastUsed = lastUsed
    }

    /// Index of the row the picker should preselect. Always in range when non-empty.
    public var preselectedIndex: Int {
        guard !profiles.isEmpty else { return 0 }
        if let lastUsed, let i = profiles.firstIndex(where: { $0.directory == lastUsed }) {
            return i
        }
        return 0
    }

    public func profile(withDirectory directory: String) -> ChromiumProfile? {
        profiles.first { $0.directory == directory }
    }
}

public enum LocalStateParser {
    /// Parse the `profile` section of a Chromium `Local State` file.
    ///
    /// Every profile in `info_cache` is reported, signed in or not.
    public static func parse(data: Data) throws -> ChromiumProfileSet {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let top = root as? [String: Any],
              let profileSection = top["profile"] as? [String: Any] else {
            return ChromiumProfileSet(profiles: [], lastUsed: nil)
        }
        let infoCache = profileSection["info_cache"] as? [String: Any] ?? [:]
        let order = profileSection["profiles_order"] as? [String] ?? []

        var parsed: [ChromiumProfile] = []
        for (directory, raw) in infoCache {
            guard let entry = raw as? [String: Any] else { continue }
            let name = entry["name"] as? String ?? directory
            let userName = entry["user_name"] as? String
            parsed.append(ChromiumProfile(
                directory: directory,
                name: name.isEmpty ? directory : name,
                userName: (userName?.isEmpty ?? true) ? nil : userName,
                themeColor: themeColor(from: entry),
                activeTime: entry["active_time"] as? Double ?? 0
            ))
        }

        // Most recently active first, so the profile you actually use lands on row 1.
        // Ties (and never-activated profiles) fall back to Chrome's own profiles_order,
        // then to the directory name, so the order is stable across runs.
        parsed.sort { a, b in
            if a.activeTime != b.activeTime { return a.activeTime > b.activeTime }
            let ia = order.firstIndex(of: a.directory) ?? Int.max
            let ib = order.firstIndex(of: b.directory) ?? Int.max
            if ia != ib { return ia < ib }
            return a.directory < b.directory
        }

        let lastUsed = profileSection["last_used"] as? String
        return ChromiumProfileSet(profiles: parsed, lastUsed: lastUsed)
    }

    /// Chrome stores colors as signed 32-bit ARGB. We only want the RGB half.
    ///
    /// `profile_color_seed` is the color the user picked; `profile_highlight_color` is
    /// Chrome's derived chrome-frame tint, which we use only as a fallback.
    static func themeColor(from entry: [String: Any]) -> UInt32? {
        for key in ["profile_color_seed", "profile_highlight_color", "default_avatar_fill_color"] {
            guard let number = entry[key] as? NSNumber else { continue }
            let argb = UInt32(bitPattern: number.int32Value)
            let rgb = argb & 0x00FF_FFFF
            // Chrome writes 0 for "no color chosen".
            if argb != 0 { return rgb }
        }
        return nil
    }

    public static func localStateURL(for browser: ChromiumBrowser,
                                     home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(browser.supportPath, isDirectory: true)
            .appendingPathComponent("Local State", isDirectory: false)
    }

    /// Read and parse the browser's `Local State`. Returns an empty set when it isn't there.
    public static func discover(browser: ChromiumBrowser,
                                home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> ChromiumProfileSet {
        let url = localStateURL(for: browser, home: home)
        guard let data = try? Data(contentsOf: url),
              let set = try? parse(data: data) else {
            return ChromiumProfileSet(profiles: [], lastUsed: nil)
        }
        return set
    }
}
