import Foundation
import AppKit
import SQLite3
import UserNotifications

/// Envoie les demandes via l'app Messages (iMessage / SMS) et lit les réponses
/// (OUI / OUI15 / NON) dans la conversation.
@MainActor
final class ApprovalService: ObservableObject {
    static let shared = ApprovalService()
    private var timer: Timer?
    private var checking = Set<UUID>()

    func start() { refreshTimer() }

    /// Le timer n'existe que s'il y a au moins une demande en attente.
    func refreshTimer() {
        let hasPending = !RulesStore.shared.pendingRequests.isEmpty
        if hasPending, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        } else if !hasPending {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Vérification manuelle d'une demande. Retourne un message pour l'utilisateur.
    func checkNow(_ r: ApprovalRequest) -> String {
        let store = RulesStore.shared
        guard canReadMessages() else {
            return "Accès refusé à Messages. Ajoute Rempart dans Accès complet au disque (puis relance l'app)."
        }
        guard let decision = findDecision(for: r) else {
            return "Pas encore de réponse (OUI / OUI15 / NON) reçue de \(r.contactName)."
        }
        apply(decision, to: r, store: store)
        refreshTimer()
        switch decision {
        case "deny": return "\(r.contactName) a refusé."
        case "approve15": return "Approuvé (15 min max)."
        default: return "Approuvé."
        }
    }

    private func apply(_ decision: String, to r: ApprovalRequest, store: RulesStore) {
        switch decision {
        case "approve": store.resolveRequest(r.id, status: .approved, grantedMinutes: r.minutes)
        case "approve15": store.resolveRequest(r.id, status: .approved, grantedMinutes: min(15, r.minutes))
        case "deny":
            store.resolveRequest(r.id, status: .denied)
            PauseNotifier.refused(by: r.contactName)
        default: break
        }
    }

    private func canReadMessages() -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(NSHomeDirectory() + "/Library/Messages/chat.db", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return false }
        defer { sqlite3_close(db) }
        var probe: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM message LIMIT 1", -1, &probe, nil) == SQLITE_OK else { return false }
        sqlite3_finalize(probe)
        return true
    }

    // MARK: Envoi
    @discardableResult
    func sendRequest(to contact: TrustedContact, items: [String], minutes: Int, message: String) async -> Bool {
        let store = RulesStore.shared
        let names = items.map(store.name(for:)).joined(separator: ", ")
        let who = NSFullUserName().isEmpty ? "Quelqu'un" : NSFullUserName()
        let first = who.split(separator: " ").first.map(String.init) ?? who
        let duration = Self.format(minutes)
        let reply = minutes > 15
            ? "Réponds OUI pour accepter, OUI15 pour 15 min seulement, ou NON."
            : "Réponds juste OUI ou NON."
        let body = """
        Salut ! \(first) aimerait utiliser \(names) pendant \(duration).

        « \(message) »

        \(reply)
        """
        guard sendMessage(to: contact.handle, text: body) else { return false }
        store.addRequest(ApprovalRequest(
            contactName: contact.name, replyTopic: contact.handle, items: items,
            minutes: minutes, message: message, created: Date(),
            status: .pending, grantedMinutes: nil, marker: nil
        ))
        refreshTimer()
        return true
    }

    @discardableResult
    func sendTest(to contact: TrustedContact) -> Bool {
        let who = NSFullUserName().isEmpty ? "Quelqu'un" : NSFullUserName()
        return sendMessage(to: contact.handle, text: """
        Rempart — test
        \(who) t'a ajouté comme proche de confiance.
        Tu recevras ici ses demandes de déblocage. Réponds simplement OUI ou NON.
        """)
    }

    static func format(_ minutes: Int) -> String {
        minutes >= 60
            ? "\(minutes / 60) h\(minutes % 60 > 0 ? " \(minutes % 60) min" : "")"
            : "\(minutes) min"
    }

    private func sendMessage(to handle: String, text: String) -> Bool {
        let h = handle.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let t = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Messages accepte un numéro ou un e-mail iMessage.
        let src = """
        tell application "Messages"
          set targetService to 1st account whose service type = iMessage
          set theBuddy to participant "\(h)" of targetService
          send "\(t)" to theBuddy
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if err == nil { return true }

        // Repli : ouvre une conversation pré-remplie (SMS/iMessage).
        let sms = "sms:" + handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            + "&body=" + text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        if let url = URL(string: sms) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    // MARK: Réponses
    private func poll() {
        let store = RulesStore.shared
        store.expireOldRequests()
        for r in store.pendingRequests where !checking.contains(r.id) {
            checking.insert(r.id)
            if let decision = findDecision(for: r) { apply(decision, to: r, store: store) }
            checking.remove(r.id)
        }
        refreshTimer()
    }

    /// Cherche une réponse OUI/NON après la date de la demande, dans Messages.
    private func findDecision(for r: ApprovalRequest) -> String? {
        let since = Int(r.created.timeIntervalSince1970) - 5
        let handle = r.replyTopic.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        // Base SQLite de Messages (nécessite « Accès complet au disque »).
        // Seuls les messages reçus APRÈS la demande comptent.
        return decisionFromChatDB(handle: handle, since: since)
    }

    private func decisionFromChatDB(handle: String, since: Int) -> String? {
        let path = NSHomeDirectory() + "/Library/Messages/chat.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        // Cherche les messages entrants récents dont l'expéditeur correspond au handle.
        let sql = """
        SELECT m.text, m.attributedBody FROM message m
        JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.is_from_me = 0
          AND m.date/1000000000 + 978307200 >= ?
          AND (REPLACE(REPLACE(REPLACE(REPLACE(LOWER(h.id),' ',''),'-',''),'(',''),')','') LIKE '%' || ? || '%'
               OR ? LIKE '%' || REPLACE(REPLACE(REPLACE(REPLACE(LOWER(h.id),' ',''),'-',''),'(',''),')','') || '%')
        ORDER BY m.date DESC LIMIT 30;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(since))
        let digits = handle.filter(\.isNumber)
        let key = digits.count >= 7 ? String(digits) : handle
        key.withCString { c1 in
            sqlite3_bind_text(stmt, 2, c1, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            _ = key.withCString { c2 in
                sqlite3_bind_text(stmt, 3, c2, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = Self.messageText(stmt), let d = parseDecision(text) { return d }
        }
        return nil
    }

    /// Texte d'un message : colonne `text`, sinon décodage de `attributedBody` (macOS récents).
    private static func messageText(_ stmt: OpaquePointer) -> String? {
        if let c = sqlite3_column_text(stmt, 0) {
            let s = String(cString: c)
            if !s.isEmpty { return s }
        }
        let n = Int(sqlite3_column_bytes(stmt, 1))
        guard n > 0, let p = sqlite3_column_blob(stmt, 1) else { return nil }
        let bytes = [UInt8](UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        let marker = Array("NSString".utf8)
        guard let mi = bytes.indices.first(where: { i in
            i + marker.count < bytes.count && Array(bytes[i..<i + marker.count]) == marker
        }) else { return nil }
        var i = mi + marker.count
        // Cherche le séparateur 0x2B ('+') suivi de la longueur
        let limit = min(bytes.count - 2, i + 12)
        while i < limit && bytes[i] != 0x2B { i += 1 }
        guard i < limit else { return nil }
        i += 1
        var len = Int(bytes[i]); i += 1
        if len == 0x81, i + 1 < bytes.count { len = Int(bytes[i]) | (Int(bytes[i + 1]) << 8); i += 2 }
        guard len > 0, i + len <= bytes.count else { return nil }
        return String(bytes: bytes[i..<i + len], encoding: .utf8)
    }

    private func parseDecision(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
        // Mots entiers uniquement (évite de prendre un "oui" dans une phrase longue)
        let first = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? t
        switch first {
        case "OUI", "YES", "OK", "OUI15", "YES15", "APPROUVE", "APPROUVÉ", "APPROUVER":
            return (first == "OUI15" || first == "YES15") ? "approve15" : "approve"
        case "NON", "NO", "REFUS", "REFUSE", "REFUSÉ":
            return "deny"
        default:
            if t == "OUI15" || t.hasPrefix("OUI15") { return "approve15" }
            if t == "OUI" || t == "YES" || t == "OK" { return "approve" }
            if t == "NON" || t == "NO" { return "deny" }
            return nil
        }
    }
}

/// Notifications locales : la pause ne vole pas le focus, elle prévient dans le Centre de notifications.
@MainActor
enum PauseNotifier {
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func started(names: String, minutes: Int, by: String?) {
        let who = by.map { "\($0) t'accorde " } ?? ""
        deliver(id: "pause-start", title: "Pause commencée",
                body: "\(who)\(ApprovalService.format(minutes)) pour \(names).")
    }

    static func endingSoon(names: String) {
        deliver(id: "pause-soon", title: "Plus qu'une minute",
                body: "\(names) se rebloque dans une minute.")
    }

    static func ended(names: String) {
        deliver(id: "pause-end", title: "Pause terminée",
                body: "\(names) est de nouveau bloqué.")
    }

    static func refused(by: String) {
        deliver(id: "pause-no", title: "Demande refusée",
                body: "\(by) a répondu NON.")
    }

    private static func deliver(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id + UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
