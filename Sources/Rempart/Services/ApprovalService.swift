import Foundation
import AppKit

/// Envoie les demandes aux proches via ntfy.sh (notifications push gratuites, sans compte)
/// et attend leur réponse sur un sujet de réponse unique.
@MainActor
final class ApprovalService: ObservableObject {
    static let shared = ApprovalService()
    static let server = "https://ntfy.sh"
    private var timer: Timer?
    private var checking = Set<UUID>()

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    static func subscribeURL(for c: TrustedContact) -> URL { URL(string: "\(server)/\(c.topic)")! }

    // MARK: Envoi
    func sendRequest(to contact: TrustedContact, items: [String], minutes: Int, message: String) async -> Bool {
        let store = RulesStore.shared
        let rand = (0..<24).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! }
        let reply = "rempart-reply-" + String(rand)
        let names = items.map(store.name(for:)).joined(separator: ", ")
        let who = NSFullUserName().isEmpty ? "Quelqu'un" : NSFullUserName()
        let duration = minutes >= 60 ? "\(minutes / 60) h\(minutes % 60 > 0 ? " \(minutes % 60) min" : "")" : "\(minutes) min"
        let body = "Veut utiliser : \(names)\nDurée demandée : \(duration)\n\n« \(message) »"

        func action(_ label: String, _ payload: String) -> [String: Any] {
            ["action": "http", "label": label, "url": "\(Self.server)/\(reply)",
             "method": "POST", "body": payload, "clear": true]
        }
        let json: [String: Any] = [
            "topic": contact.topic,
            "title": "\(who) demande un déblocage",
            "message": body,
            "priority": 4,
            "tags": ["hourglass_flowing_sand"],
            "actions": [action("Approuver (\(duration))", "approve"),
                        action("Approuver 15 min", "approve15"),
                        action("Refuser", "deny")]
        ]
        guard await publish(json) else { return false }
        store.addRequest(ApprovalRequest(contactName: contact.name, replyTopic: reply, items: items,
                                         minutes: minutes, message: message, created: Date()))
        return true
    }

    func sendTest(to contact: TrustedContact) async -> Bool {
        let who = NSFullUserName().isEmpty ? "Quelqu'un" : NSFullUserName()
        return await publish([
            "topic": contact.topic,
            "title": "Rempart : test",
            "message": "\(who) t'a ajouté comme proche de confiance. Tu recevras ici ses demandes de déblocage.",
            "tags": ["white_check_mark"]
        ])
    }

    private func publish(_ json: [String: Any]) async -> Bool {
        guard let url = URL(string: Self.server),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    // MARK: Réponses
    private func poll() {
        let store = RulesStore.shared
        store.expireOldRequests()
        for r in store.pendingRequests where !checking.contains(r.id) {
            checking.insert(r.id)
            Task {
                await check(r)
                checking.remove(r.id)
            }
        }
    }

    private func check(_ r: ApprovalRequest) async {
        guard let url = URL(string: "\(Self.server)/\(r.replyTopic)/json?poll=1&since=all"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8) else { return }
        var decision: String?
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  obj["event"] as? String == "message",
                  let msg = obj["message"] as? String else { continue }
            decision = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch decision {
        case "approve": RulesStore.shared.resolveRequest(r.id, status: .approved, grantedMinutes: r.minutes)
        case "approve15": RulesStore.shared.resolveRequest(r.id, status: .approved, grantedMinutes: min(15, r.minutes))
        case "deny": RulesStore.shared.resolveRequest(r.id, status: .denied)
        default: break
        }
    }
}
