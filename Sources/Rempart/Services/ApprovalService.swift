import Foundation
import AppKit
import SQLite3

/// Envoie les demandes via l'app Messages (iMessage / SMS) et lit les réponses
/// (OUI / OUI15 / NON) dans la conversation.
@MainActor
final class ApprovalService: ObservableObject {
    static let shared = ApprovalService()
    private var timer: Timer?
    private var checking = Set<UUID>()

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    // MARK: Envoi
    @discardableResult
    func sendRequest(to contact: TrustedContact, items: [String], minutes: Int, message: String) async -> Bool {
        let store = RulesStore.shared
        let names = items.map(store.name(for:)).joined(separator: ", ")
        let who = NSFullUserName().isEmpty ? "Quelqu'un" : NSFullUserName()
        let duration = Self.format(minutes)
        let body = """
        Rempart — demande de déblocage
        De : \(who)
        Veut utiliser : \(names)
        Durée : \(duration)

        « \(message) »

        Réponds par un seul mot :
        • OUI — pour approuver (\(duration))
        • OUI15 — pour 15 minutes seulement
        • NON — pour refuser
        """
        let token = (0..<8).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }
        let marker = String(token)
        let full = body + "\n\n#\(marker)"
        guard sendMessage(to: contact.handle, text: full) else { return false }
        store.addRequest(ApprovalRequest(
            contactName: contact.name, replyTopic: contact.handle, items: items,
            minutes: minutes, message: message, created: Date(),
            status: .pending, grantedMinutes: nil, marker: marker
        ))
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
            if let decision = findDecision(for: r) {
                switch decision {
                case "approve": store.resolveRequest(r.id, status: .approved, grantedMinutes: r.minutes)
                case "approve15": store.resolveRequest(r.id, status: .approved, grantedMinutes: min(15, r.minutes))
                case "deny": store.resolveRequest(r.id, status: .denied)
                default: break
                }
            }
            checking.remove(r.id)
        }
    }

    /// Cherche une réponse OUI/NON après la date de la demande, dans Messages.
    private func findDecision(for r: ApprovalRequest) -> String? {
        let since = Int(r.created.timeIntervalSince1970) - 5
        let handle = r.replyTopic.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        // 1) AppleScript : dernier message reçu du contact
        if let text = lastIncomingMessage(from: r.replyTopic),
           let d = parseDecision(text) { return d }

        // 2) Base SQLite de Messages (nécessite « Accès complet au disque »)
        return decisionFromChatDB(handle: handle, since: since)
    }

    private func lastIncomingMessage(from handle: String) -> String? {
        let h = handle.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = """
        tell application "Messages"
          try
            set targetService to 1st account whose service type = iMessage
            set theBuddy to participant "\(h)" of targetService
            set chats to chats whose participants contains theBuddy
            if (count of chats) is 0 then return ""
            set theChat to item 1 of chats
            set msgs to messages of theChat
            if (count of msgs) is 0 then return ""
            set lastMsg to item -1 of msgs
            if direction of lastMsg is incoming then
              return text of lastMsg as string
            end if
            return ""
          on error
            return ""
          end try
        end tell
        """
        var err: NSDictionary?
        let result = NSAppleScript(source: src)?.executeAndReturnError(&err)
        let s = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    private func decisionFromChatDB(handle: String, since: Int) -> String? {
        let path = NSHomeDirectory() + "/Library/Messages/chat.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        // Cherche les messages entrants récents dont l'expéditeur correspond au handle.
        let sql = """
        SELECT m.text FROM message m
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
            key.withCString { c2 in
                sqlite3_bind_text(stmt, 3, c2, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            if let d = parseDecision(String(cString: c)) { return d }
        }
        return nil
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
