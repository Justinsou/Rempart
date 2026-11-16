import Foundation
import SwiftUI

@MainActor
final class RulesStore: ObservableObject {
    static let shared = RulesStore()

    @Published private(set) var state = AppState()
    @Published var now = Date()

    private let supportDir: URL
    private let stateURL: URL
    static let hostsRulesDir = "/Users/Shared/Rempart"
    static let hostsRulesPath = "/Users/Shared/Rempart/hosts-rules.txt"
    private var timer: Timer?

    var apps: [BlockedApp] { state.apps }
    var sites: [BlockedSite] { state.sites }
    var journal: [JournalEntry] { state.journal.sorted { $0.date > $1.date } }
    var onboarded: Bool { state.onboarded }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("Rempart", isDirectory: true)
        stateURL = supportDir.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        load()
        syncHosts()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: Persistance
    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(AppState.self, from: data) else { return }
        state = s
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .deferredToDate
        if let data = try? enc.encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func mutate(_ f: (inout AppState) -> Void) {
        f(&state)
        save()
        syncHosts()
    }

    private func tick() {
        now = Date()
        if state.sessions.contains(where: { $0.end <= now }) {
            mutate { $0.sessions.removeAll { $0.end <= Date() } }
        }
    }

    // MARK: Règles
    func setOnboarded() { mutate { $0.onboarded = true } }

    func isAppListed(_ id: String) -> Bool { state.apps.contains { $0.bundleID == id } }
    func isSiteListed(_ d: String) -> Bool { state.sites.contains { $0.domain == d } }

    /// Ajoute toujours ; retire seulement si autorisé. Retourne false si refusé.
    @discardableResult
    func toggleApp(_ app: BlockedApp) -> Bool {
        if let i = state.apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
            guard canRemoveApp(app.bundleID) else { return false }
            mutate { $0.apps.remove(at: i) }
        } else {
            mutate { $0.apps.append(app) }
        }
        return true
    }

    @discardableResult
    func addSite(_ raw: String) -> Bool {
        guard let d = Self.normalize(raw), !isSiteListed(d) else { return false }
        mutate { $0.sites.append(BlockedSite(domain: d)) }
        return true
    }

    @discardableResult
    func removeSite(_ s: BlockedSite) -> Bool {
        guard canRemoveSite(s.domain) else { return false }
        mutate { $0.sites.removeAll { $0.domain == s.domain } }
        return true
    }

    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let u = URLComponents(string: s), let h = u.host { s = h }
        s = s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        let regex = #"^([a-z0-9-]+\.)+[a-z]{2,}$"#
        return s.range(of: regex, options: .regularExpression) != nil ? s : nil
    }

    // MARK: Déblocages
    private func unlockEnd(for key: String) -> Date? {
        state.sessions.filter { $0.items.contains(key) && $0.start <= now && $0.end > now }
            .map(\.end).max()
    }

    /// Retirer un élément n'est permis que s'il est débloqué en ce moment
    /// (ou pendant la configuration initiale).
    func isAppUnlockedNow(_ bundleID: String) -> Bool { unlockEnd(for: "app:" + bundleID) != nil }
    func isSiteUnlockedNow(_ domain: String) -> Bool { unlockEnd(for: "site:" + domain) != nil }
    func canRemoveApp(_ id: String) -> Bool { !state.onboarded || isAppUnlockedNow(id) }
    func canRemoveSite(_ domain: String) -> Bool { !state.onboarded || isSiteUnlockedNow(domain) }

    func isAppBlocked(_ bundleID: String) -> Bool {
        guard isAppListed(bundleID) else { return false }
        return unlockEnd(for: "app:" + bundleID) == nil
    }

    func isSiteBlocked(host: String) -> String? {
        let h = host.lowercased()
        for s in state.sites where h == s.domain || h.hasSuffix("." + s.domain) {
            if unlockEnd(for: s.key) == nil { return s.domain }
        }
        return nil
    }

    var activeSessions: [UnlockSession] {
        state.sessions.filter { $0.start <= now && $0.end > now }.sorted { $0.end < $1.end }
    }

    func name(for key: String) -> String {
        if key.hasPrefix("app:") {
            let id = String(key.dropFirst(4))
            return state.apps.first { $0.bundleID == id }?.name ?? id
        }
        return String(key.dropFirst(5))
    }

    func addUnlock(items: [String], minutes: Int, reason: String) {
        let start = Date()
        let end = start.addingTimeInterval(Double(minutes) * 60)
        let session = UnlockSession(items: items, start: start, end: end, reason: reason)
        let entry = JournalEntry(date: start, reason: reason, itemNames: items.map(name(for:)), minutes: minutes)
        mutate { $0.sessions.append(session); $0.journal.append(entry) }
    }

    func endSession(_ s: UnlockSession) { mutate { $0.sessions.removeAll { $0.id == s.id } } }

    // MARK: Statistiques
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func recordBlock() {
        let k = Self.dayFormatter.string(from: Date())
        state.blockCounts[k, default: 0] += 1
        save()
    }

    func lastDays(_ n: Int) -> [(label: String, count: Int)] {
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEEEE"
        return (0..<n).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: now) ?? now
            return (f.string(from: d).uppercased(), state.blockCounts[Self.dayFormatter.string(from: d)] ?? 0)
        }
    }

    var blocksToday: Int { state.blockCounts[Self.dayFormatter.string(from: now)] ?? 0 }

    // MARK: Fichier hosts (lu par le service système)
    func syncHosts() {
        var lines: [String] = []
        for s in state.sites {
            if let end = unlockEnd(for: s.key) {
                lines.append("\(s.domain) \(Int(end.timeIntervalSince1970))")
            } else {
                lines.append(s.domain)
            }
        }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.hostsRulesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o755])
        try? (lines.joined(separator: "\n") + "\n").write(toFile: Self.hostsRulesPath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.hostsRulesPath)
    }
}
