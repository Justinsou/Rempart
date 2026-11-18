import Foundation
import SwiftUI
import AppKit

@MainActor
final class RulesStore: ObservableObject {
    static let shared = RulesStore()

    @Published private(set) var state = AppState()
    @Published var now = Date()
    /// Dernière pause commencée, pour l'afficher une fois. L'utilisateur la ferme ; le compte à rebours reste.
    @Published var freshPause: UnlockSession?

    private let supportDir: URL
    private let stateURL: URL
    static let hostsRulesDir = "/Users/Shared/Rempart"
    static let hostsRulesPath = "/Users/Shared/Rempart/hosts-rules.txt"
    static let appsRulesPath = "/Users/Shared/Rempart/apps-rules.txt"
    private var timer: Timer?

    var apps: [BlockedApp] { state.apps }
    var sites: [BlockedSite] { state.sites }
    var journal: [JournalEntry] { state.journal.sorted { $0.date > $1.date } }
    var onboarded: Bool { state.onboarded }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("Rempart", isDirectory: true)
        stateURL = supportDir.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDir.path)
        load()
        syncHosts()
        updateTimer()
    }

    /// Le timer d'1 s n'existe que tant qu'un déblocage est actif.
    private func updateTimer() {
        if state.sessions.isEmpty {
            timer?.invalidate(); timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    // MARK: Persistance
    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              var s = try? JSONDecoder().decode(AppState.self, from: data) else { return }
        // Nettoie les anciens contacts ntfy (sans vrai numéro / e-mail).
        s.contacts.removeAll { $0.handle.isEmpty || $0.handle.hasPrefix("rempart-") }
        state = s
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .deferredToDate
        if let data = try? enc.encode(state) {
            try? data.write(to: stateURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
    }

    private func mutate(_ f: (inout AppState) -> Void) {
        now = Date()
        f(&state)
        save()
        syncHosts()
        updateTimer()
    }

    private var warned = Set<UUID>()

    private func tick() {
        now = Date()
        for s in state.sessions where !warned.contains(s.id) {
            let left = s.end.timeIntervalSince(now)
            if left > 0, left <= 60 {
                warned.insert(s.id)
                PauseNotifier.endingSoon(names: s.items.map(name(for:)).joined(separator: ", "))
            }
        }
        let ended = state.sessions.filter { $0.end <= now }
        if !ended.isEmpty {
            mutate { $0.sessions.removeAll { $0.end <= Date() } }
            for s in ended { warned.remove(s.id) }
            PauseNotifier.ended(names: ended.flatMap(\.items).map(name(for:)).joined(separator: ", "))
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
        freshPause = session
        let by = reason.hasPrefix("Approuvé par ")
            ? String(reason.dropFirst("Approuvé par ".count).prefix(while: { $0 != "—" }).trimmingCharacters(in: .whitespaces))
            : nil
        PauseNotifier.started(names: items.map(name(for:)).joined(separator: ", "), minutes: minutes, by: by)
    }

    func endSession(_ s: UnlockSession) { mutate { $0.sessions.removeAll { $0.id == s.id } } }

    // MARK: Statistiques
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func recordBlock() {
        now = Date()
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

        // Règles d'apps : le service système ferme ces apps même si Rempart est quitté.
        // Format : "<fin_du_déblocage_epoch ou 0>|<chemin de l'app>"
        var appLines: [String] = []
        for a in state.apps {
            let path = a.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundleID)?.path
            guard let path, path.hasSuffix(".app"), !path.contains("|"), !path.contains("\n") else { continue }
            let until = unlockEnd(for: a.key).map { Int($0.timeIntervalSince1970) } ?? 0
            appLines.append("\(until)|\(path)")
        }
        try? (appLines.joined(separator: "\n") + "\n").write(toFile: Self.appsRulesPath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.appsRulesPath)
    }

    // MARK: Proches et demandes d'approbation
    var contacts: [TrustedContact] { state.contacts }
    var requests: [ApprovalRequest] { state.requests.sorted { $0.created > $1.created } }
    var pendingRequests: [ApprovalRequest] { state.requests.filter { $0.status == .pending } }

    @discardableResult
    func addContact(name: String, handle: String) -> TrustedContact? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !n.isEmpty, !h.isEmpty else { return nil }
        // Ignore les anciens contacts ntfy (topic sans @ ni chiffre).
        let c = TrustedContact(name: n, handle: h)
        mutate {
            $0.contacts.removeAll { $0.handle.isEmpty || $0.handle.hasPrefix("rempart-") }
            $0.contacts.append(c)
        }
        return c
    }

    func removeContact(_ c: TrustedContact) { mutate { $0.contacts.removeAll { $0.id == c.id } } }

    func addRequest(_ r: ApprovalRequest) { mutate { $0.requests.append(r) } }

    func resolveRequest(_ id: UUID, status: RequestStatus, grantedMinutes: Int? = nil) {
        guard let r = state.requests.first(where: { $0.id == id }), r.status == .pending else { return }
        mutate {
            if let i = $0.requests.firstIndex(where: { $0.id == id }) {
                $0.requests[i].status = status
                $0.requests[i].grantedMinutes = grantedMinutes
            }
        }
        if status == .approved, let m = grantedMinutes {
            addUnlock(items: r.items, minutes: m, reason: "Approuvé par \(r.contactName) — « \(r.message) »")
        }
    }

    func cancelRequest(_ id: UUID) {
        resolveRequest(id, status: .cancelled)
        ApprovalService.shared.refreshTimer()
    }

    func deleteRequest(_ id: UUID) {
        mutate { $0.requests.removeAll { $0.id == id && $0.status != .pending } }
    }

    func deleteFinishedRequests() {
        mutate { $0.requests.removeAll { $0.status != .pending } }
    }

    func expireOldRequests() {
        let limit = Date().addingTimeInterval(-3600)
        for r in state.requests where r.status == .pending && r.created < limit {
            resolveRequest(r.id, status: .expired)
        }
    }
}
