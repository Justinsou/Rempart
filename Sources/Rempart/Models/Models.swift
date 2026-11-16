import Foundation

struct BlockedApp: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
    var key: String { "app:" + bundleID }
}

struct BlockedSite: Codable, Identifiable, Hashable {
    var domain: String
    var id: String { domain }
    var key: String { "site:" + domain }
}

struct UnlockSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var items: [String]          // "app:<bundleID>" ou "site:<domain>"
    var start: Date
    var end: Date
    var reason: String
}

struct JournalEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var reason: String
    var itemNames: [String]
    var minutes: Int
}

struct AppState: Codable {
    var apps: [BlockedApp] = []
    var sites: [BlockedSite] = []
    var sessions: [UnlockSession] = []
    var journal: [JournalEntry] = []
    var blockCounts: [String: Int] = [:]
    var onboarded = false
}

enum Suggestions {
    static let sites: [(name: String, domain: String)] = [
        ("YouTube", "youtube.com"), ("Instagram", "instagram.com"),
        ("TikTok", "tiktok.com"), ("Facebook", "facebook.com"),
        ("X", "x.com"), ("Reddit", "reddit.com"), ("Netflix", "netflix.com"),
        ("Twitch", "twitch.tv"), ("Disney+", "disneyplus.com")
    ]
}
