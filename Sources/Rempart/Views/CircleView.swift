import SwiftUI
import AppKit

struct CircleView: View {
    @EnvironmentObject var store: RulesStore
    @State private var name = ""
    @State private var feedback: [UUID: String] = [:]

    private let moods: [Mood] = [.happy, .sad, .angry, .sleepy]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Proches",
                           subtitle: "Des personnes de confiance qui décident si tu peux débloquer.",
                           mood: .happy)

                Card {
                    Text("Comment ça marche").caption2Label()
                    step(1, "Ajoute un proche ci-dessous (2 personnes max recommandé).")
                    step(2, "Il installe l'app gratuite **ntfy** (iPhone ou Android), puis ouvre le lien que tu lui envoies.")
                    step(3, "Quand tu demandes un déblocage, il reçoit une notification avec ton message et les boutons Approuver / Refuser.")
                }

                HStack(spacing: 12) {
                    SearchField(text: $name, placeholder: "Prénom du proche", icon: "person.badge.plus", onSubmit: add)
                    PillButton(title: "Ajouter", icon: "plus", action: add)
                        .scaleEffect(1.1).padding(.horizontal, 6)
                }

                if store.contacts.isEmpty {
                    VStack(spacing: 10) {
                        BlobView(mood: .calm, size: 90)
                        Text("Aucun proche pour l'instant").foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }

                ForEach(Array(store.contacts.enumerated()), id: \.element.id) { i, c in
                    Card {
                        HStack(spacing: 14) {
                            BlobView(mood: moods[i % moods.count], size: 52, glow: false, float: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name).font(.system(size: 17, weight: .bold, design: .rounded))
                                Text(ApprovalService.subscribeURL(for: c).absoluteString)
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            ShareLink(item: ApprovalService.subscribeURL(for: c),
                                      message: Text("Installe l'app ntfy puis ouvre ce lien pour recevoir mes demandes de déblocage Rempart.")) {
                                Label("Envoyer le lien", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Theme.accent, in: Capsule())
                                    .foregroundStyle(Color(red: 0.03, green: 0.12, blue: 0.2))
                            }
                            .buttonStyle(.plain)
                            PillButton(title: "Copier", icon: "doc.on.doc", style: .subtle) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ApprovalService.subscribeURL(for: c).absoluteString, forType: .string)
                                feedback[c.id] = "Lien copié"
                            }
                            PillButton(title: "Notification test", icon: "bell", style: .subtle) {
                                feedback[c.id] = "Envoi…"
                                Task {
                                    let ok = await ApprovalService.shared.sendTest(to: c)
                                    feedback[c.id] = ok ? "Test envoyé" : "Échec : vérifie ta connexion"
                                }
                            }
                            Spacer()
                            PillButton(title: "Retirer", icon: "trash", style: .danger) { store.removeContact(c) }
                        }
                        if let f = feedback[c.id] {
                            Text(f).font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }

                Banner(icon: "info.circle", text: "Les notifications passent par ntfy.sh. Le lien contient un code secret : ne le partage qu'avec la personne concernée.")
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.03, green: 0.12, blue: 0.2))
                .frame(width: 20, height: 20).background(Theme.accent, in: Circle())
            Text(text).font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func add() {
        if store.addContact(name: name) != nil { name = "" }
    }
}
