import Foundation

/// A trimmed-down copy of a real Chrome `Local State`, with the fields we read.
/// Colors are stored the way Chrome stores them: signed 32-bit ARGB.
enum Fixtures {
    static let twoProfiles = """
    {
      "profile": {
        "last_used": "Profile 3",
        "profiles_order": ["Default", "Profile 3"],
        "info_cache": {
          "Default": {
            "active_time": 1790044215.28327,
            "name": "Personal",
            "user_name": "personal@example.com",
            "profile_color_seed": -5715974,
            "profile_highlight_color": -14737376
          },
          "Profile 3": {
            "active_time": 1790044221.770913,
            "name": "Work",
            "user_name": "work@example.com",
            "profile_color_seed": -1499549,
            "profile_highlight_color": -14737376
          }
        }
      }
    }
    """.data(using: .utf8)!

    /// Three profiles, one never signed in and never activated.
    static let threeProfiles = """
    {
      "profile": {
        "last_used": "Profile 3",
        "profiles_order": ["Default", "Profile 2", "Profile 3"],
        "info_cache": {
          "Default": {
            "active_time": 1790044215.0,
            "name": "Personal",
            "user_name": "personal@example.com"
          },
          "Profile 2": {
            "active_time": 0,
            "name": "Profile 2",
            "user_name": ""
          },
          "Profile 3": {
            "active_time": 1790044221.0,
            "name": "Work",
            "user_name": "work@example.com"
          }
        }
      }
    }
    """.data(using: .utf8)!

    static let singleProfile = """
    {
      "profile": {
        "last_used": "Default",
        "info_cache": {
          "Default": { "active_time": 1.0, "name": "Person 1", "user_name": "solo@example.com" }
        }
      }
    }
    """.data(using: .utf8)!

    /// Safari-shaped nonsense: no `profile` key at all.
    static let notChromium = #"{"some":"other file"}"#.data(using: .utf8)!
}
