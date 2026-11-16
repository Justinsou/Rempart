import SwiftUI
import AppKit

struct CircleView: View {
    @EnvironmentObject var store: RulesStore
    @State private var name = ""
    @State private var handle = ""
    @State private var feedback: [UUID: String] = [:]
    @State private var formError: String?

    private let moods: [Mood] = [.happy, .sad, .angry, .sleepy]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Proches",
                           subtitle: "Ils reçoivent ta demande dans Messages et répondent OUI ou NON.",
                           mood: .happy)

                Card {
                    Text("Comment ça marche").caption2Label()
                    step(1, "Ajoute un proche avec son numéro ou son e-mail iMessage.")
                    step(2, "Quand tu demandes un déblocage, Rempart lui envoie un message.")
                    step(3, "Il répond **OUI**, **OUI15** (15 min) ou **NON**. Rempart lit la réponse et débloque automatiquement.")
                }

                Card {
                    Text("Nouveau proche").caption2Label()
                    HStack(spacing: 12) {
                        SearchField(text: $name, placeholder: "Prénom", icon: "person")
                        SearchField(text: $handle, placeholder: "Numéro ou e-mail iMessage", icon: "phone", onSubmit: add)
                    }
                    if let formError {
                        Text(formError).font(.caption).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.5))
                    }
                    HStack {
                        Spacer()
                        PillButton(title: "Ajouter", icon: "plus", action: add)
                    }
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
                                Text(c.handle).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            PillButton(title: "Message test", icon: "paperplane", style: .subtle) {
                                feedback[c.id] = ApprovalService.shared.sendTest(to: c)
                                    ? "Message ouvert / envoyé" : "Échec : autorise Rempart à contrôler Messages"
                            }
                            Spacer()
                            PillButton(title: "Retirer", icon: "trash", style: .danger) { store.removeContact(c) }
                        }
                        if let f = feedback[c.id] {
                            Text(f).font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }

                Banner(icon: "lock.rectangle",
                       text: "Pour lire les réponses, Rempart doit être dans Réglages → Confidentialité → Accès complet au disque (puis relance Rempart). Pour envoyer, autorise aussi Automatisation → Messages.")
                HStack {
                    PillButton(title: "Ouvrir Accès complet au disque", icon: "gearshape", style: .subtle) {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(u)
                        }
                    }
                    Spacer()
                }
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
        formError = nil
        if store.addContact(name: name, handle: handle) != nil {
            name = ""; handle = ""
        } else {
            formError = "Indique un prénom et un numéro ou e-mail iMessage."
        }
    }
}
