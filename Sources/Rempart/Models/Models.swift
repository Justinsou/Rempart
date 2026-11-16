import Foundation

struct BlockedApp: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var path: String?
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

/// Un proche qui peut approuver ou refuser une demande (via notification ntfy).
struct TrustedContact: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var topic: String
}

enum RequestStatus: String, Codable { case pending, approved, denied, expired }

struct ApprovalRequest: Codable, Identifiable, Hashable {
    var id = UUID()
    var contactName: String
    var replyTopic: String
    var items: [String]
    var minutes: Int
    var message: String
    var created: Date
    var status: RequestStatus = .pending
    var grantedMinutes: Int?
}

struct AppState: Codable {
    var apps: [BlockedApp] = []
    var sites: [BlockedSite] = []
    var sessions: [UnlockSession] = []
    var journal: [JournalEntry] = []
    var blockCounts: [String: Int] = [:]
    var onboarded = false
    var contacts: [TrustedContact] = []
    var requests: [ApprovalRequest] = []

    init() {}

    // Décodage tolérant : les anciens fichiers d'état n'ont pas les nouvelles clés.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([BlockedApp].self, forKey: .apps) ?? []
        sites = try c.decodeIfPresent([BlockedSite].self, forKey: .sites) ?? []
        sessions = try c.decodeIfPresent([UnlockSession].self, forKey: .sessions) ?? []
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? []
        blockCounts = try c.decodeIfPresent([String: Int].self, forKey: .blockCounts) ?? [:]
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        contacts = try c.decodeIfPresent([TrustedContact].self, forKey: .contacts) ?? []
        requests = try c.decodeIfPresent([ApprovalRequest].self, forKey: .requests) ?? []
    }
}

enum Suggestions {
    static let sites: [(name: String, domain: String)] = [
        ("YouTube", "youtube.com"), ("Instagram", "instagram.com"),
        ("TikTok", "tiktok.com"), ("Facebook", "facebook.com"),
        ("X", "x.com"), ("Reddit", "reddit.com"), ("Netflix", "netflix.com"),
        ("Twitch", "twitch.tv"), ("Disney+", "disneyplus.com")
    ]
}
